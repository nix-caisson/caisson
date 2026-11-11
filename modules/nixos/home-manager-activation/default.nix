# SPDX-License-Identifier: MIT
#
# A NixOS module with which a NixOS configuration activates the
# home-manager configurations declared inside it.
#
# Activating a home-manager configuration means running the `activate`
# script of its activation package as the user of the home-manager
# configuration. The script links the files of the home-manager
# configuration into the home directory and installs its packages.
# home-manager has a NixOS module that does this for the home-manager
# configurations it embeds. caisson does not use that NixOS module. A
# home-manager configuration declared inside a NixOS configuration is a
# caisson configuration, and this module writes the systemd units that
# activate it, so that switching to a new generation of the NixOS
# configuration also applies its home-manager configurations.
#
# caisson's `default` NixOS module imports this module. A NixOS
# configuration that passes `moduleImports` selects its modules
# itself, and then its home-manager configurations are activated only
# if it lists this module.
#
# Which home-manager configurations
#
# The module activates the home-manager configurations that this
# NixOS configuration passes up: the home-manager configurations
# declared inside it, also through a structural configuration, that its
# `caisson.home-manager.exported` selector selects. It leaves out
# these. A home-manager configuration declared inside a NixOS,
# nix-darwin or system-manager configuration that is itself declared
# inside this NixOS configuration belongs to that inner configuration. A
# home-manager configuration evaluated for a system other than the
# system of this NixOS configuration cannot run here.
#
# Which unit
#
# The module expects the NixOS configuration to declare the account of the user
# of each home-manager configuration in `users.users`. For such an
# account, the unit is a system unit named `home-manager-<user>`. It
# runs as that user during boot, before users can log in. This is the
# unit home-manager's NixOS module writes.
#
# A home-manager configuration whose user has no account in
# `users.users` is refused, with an assertion that names the
# home-manager configuration and the user. In most NixOS configurations
# such a home-manager configuration is a mistake: a misspelled user
# name, or a home-manager configuration declared inside the wrong NixOS
# configuration.
#
# Some accounts are provided by something other than `users.users`. An
# account that systemd-homed manages is such an account. The NixOS
# configuration must not declare such an account, because systemd-homed
# keeps the record of it, and its home directory is mounted only at
# login. The option
# `caisson.home-manager.activation.usersDeclaredElsewhere` lists the
# users that have such an account on the computers that run this NixOS
# configuration.
#
# For a user in that list, the unit is a user unit named
# `home-manager-<user>`, with `ConditionUser=<user>`. It runs when the
# service manager of that user starts, which is at login.
#
# The profile of the home-manager configuration
#
# Both units run `activate` with no driver version, which is what
# home-manager calls the legacy behavior: the script also updates the
# home-manager profile of the user. The user can then run
# `home-manager switch` and `home-manager generations` on the same
# profile. home-manager's NixOS module passes `--driver-version 1`,
# which leaves the profile alone.
#
# The packages of the home-manager configuration
#
# By default the `activate` script also installs the packages of the
# home-manager configuration, `home.path`, into a profile in the home
# directory. A home-manager configuration that sets
# `caisson.useUserPackages` leaves its packages to the configuration it
# is declared inside, and in a NixOS configuration this module installs
# them in `/etc/profiles/per-user/<user>`, which NixOS builds as part of
# the system. A switch of the NixOS configuration then changes them
# while the home directory is locked. For an account the NixOS
# configuration declares, the module
# adds `home.path` to `users.users.<user>.packages`, as home-manager's
# NixOS module does with `home-manager.useUserPackages`. For a user
# listed in `usersDeclaredElsewhere`, which has no entry in
# `users.users`, the module builds `/etc/profiles/per-user/<user>` from
# `home.path` as NixOS builds it from `users.users.<user>.packages`.
# The module reads the path of the profile and what it holds from the
# profile adapter of the home-manager configuration
# (`activation.profileAdapter` of the home-manager integration).
#
# The module reads the home-manager configurations from the result of
# the full evaluation of the NixOS configuration. The childless
# evaluation leaves out the configurations declared inside the NixOS
# configuration, so there the module defines nothing.
#
# The nixos-minimal integration evaluates NixOS with a module list
# that has no systemd options and no assertions. A NixOS configuration
# of that kind cannot run units, so there the module also defines
# nothing.
#
# The same module is registered for the `systemManager` class, under
# the same name, and a system-manager configuration activates the
# home-manager configurations declared inside it the same way:
# system-manager declares `users.users` and runs the units, and starts
# those wanted by `multi-user.target` with `system-manager.target`. The
# module reads `config.caisson.exports.configurations`, which the core
# module declares; it imports the core module of the class of the
# configuration, read from its manifest.
{ closure-lib, ... }:
{
  config,
  lib,
  options,
  pkgs,
  utils,
  ...
}:
let
  inherit (lib.caisson) evalManifest;

  # True when this configuration declares the options the module defines.
  hasUnits =
    options ? assertions
    && options ? systemd
    && options.systemd ? services
    && options.systemd ? user
    && options ? users;

  # True when this configuration declares the options with which the
  # module installs packages for a user, as a NixOS configuration does.
  hasUserPackages =
    !onSystemManager
    && options ? environment
    && options.environment ? etc
    && options.environment ? pathsToLink;

  # The core module of the class of this configuration: of the
  # `systemManager` class in a system-manager configuration, else of the
  # `nixos` class. The registered core modules of the two classes are
  # the same file under two names, so a module imports the name its
  # configuration already holds.
  coreModule =
    if (lib.caisson-core.evalManifest.type or null) == "system-manager" then
      closure-lib.caisson.modules.systemManager.core
    else
      closure-lib.caisson.modules.nixos.core;

  # The integrations of the NixOS, nix-darwin and system-manager
  # configurations, which activate the home-manager configurations
  # declared inside them.
  systemConfigurationTypes = [
    "nixos"
    "darwin"
    "system-manager"
  ];

  # True for an entry this NixOS configuration activates. `entry.path`
  # is the path from this NixOS configuration to the configuration of
  # the entry, a list of `{ type, name }` segments.
  isActivatedHere =
    entry:
    let
      above = lib.lists.init entry.path;
    in
    entry.manifest.type == "home-manager"
    # A NixOS, nix-darwin or system-manager configuration on the path is
    # declared inside this NixOS configuration, and the home-manager
    # configuration belongs to it.
    && !(builtins.any (segment: builtins.elem segment.type systemConfigurationTypes) above)
    && entry.manifest.system == evalManifest.system;

  # What the units need of each home-manager configuration.
  homeManagerConfigurations = builtins.map (entry: {
    # The name the home-manager configuration is published under, for
    # messages.
    name = entry.manifest.name;
    inherit (entry.value.config.home) username homeDirectory;
    inherit (entry.value) activationPackage;
    # The profile that holds the packages of the home-manager
    # configuration, from its profile adapter.
    packages = (entry.manifest.activation.profileAdapter entry.manifest).profiles.packages;
  }) (builtins.filter isActivatedHere config.caisson.exports.configurations);

  onSystemManager = (lib.caisson-core.evalManifest.type or null) == "system-manager";

  # The name of the integration of this configuration, for messages.
  integrationName = if onSystemManager then "system-manager" else "NixOS";

  # The home-manager configurations whose packages this NixOS
  # configuration installs (`caisson.useUserPackages`).
  installedHere = builtins.filter (
    homeManagerConfiguration: homeManagerConfiguration.packages.setBy == "machine"
  ) homeManagerConfigurations;

  # The accounts in the result of the childless evaluation of this
  # NixOS configuration. The accounts of the full evaluation include
  # the entries this module adds to `users.users`, so they cannot say
  # which accounts the NixOS configuration declares.
  declaredAccounts = (evalManifest.childlessManifest.value.config.users.users or { });

  # The environment NixOS builds for `/etc/profiles/per-user/<user>`
  # from `users.users.<user>.packages` (`nixos/modules/config/users-groups.nix`
  # of nixpkgs), here from `home.path` alone.
  userEnvironment =
    homeManagerConfiguration:
    pkgs.buildEnv {
      name = "user-environment";
      paths = [ homeManagerConfiguration.packages.holds ];
      inherit (config.environment) pathsToLink extraOutputsToInstall;
      inherit (config.system.path) ignoreCollisions postBuild;
    };

  # True when the NixOS configuration declares the account of the user
  # of the home-manager configuration in `users.users`.
  isDeclared = homeManagerConfiguration: config.users.users ? ${homeManagerConfiguration.username};

  # The users that have an account on the computers that run this NixOS
  # configuration although `users.users` does not declare it.
  elsewhere = config.caisson.home-manager.activation.usersDeclaredElsewhere;
  isElsewhere = homeManagerConfiguration: builtins.elem homeManagerConfiguration.username elsewhere;

  # The home-manager configurations whose user has no account the
  # NixOS configuration knows of: not in `users.users`, and not listed as declared
  # elsewhere. The module refuses these.
  withoutAccount = builtins.filter (
    homeManagerConfiguration:
    !(isDeclared homeManagerConfiguration) && !(isElsewhere homeManagerConfiguration)
  ) homeManagerConfigurations;

  # The users that are listed as declared elsewhere and are also in
  # `users.users`. The two statements contradict each other.
  inBoth = builtins.filter (username: config.users.users ? ${username}) elsewhere;

  unitName =
    homeManagerConfiguration:
    "home-manager-${utils.escapeSystemdPath homeManagerConfiguration.username}";

  # The settings both kinds of unit share. They are the settings of
  # the unit home-manager's NixOS module writes.
  baseUnit = homeManagerConfiguration: {
    description = "Home Manager environment for ${homeManagerConfiguration.username}";
    # The unit is not stopped when its definition changes. The new
    # generation of the NixOS configuration starts it again, which activates the
    # new generation of the home-manager configuration.
    stopIfChanged = false;
    environment = {
      # Programs that use Qt may run during activation, and they must
      # not look for a display.
      QT_QPA_PLATFORM = "offscreen";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5m";
      SyslogIdentifier = "hm-activate-${homeManagerConfiguration.username}";
    };
  };

  # The unit for an account the NixOS configuration declares.
  systemUnit =
    homeManagerConfiguration:
    lib.attrsets.recursiveUpdate (baseUnit homeManagerConfiguration) {
      wantedBy = [ "multi-user.target" ];
      wants = [ "nix-daemon.socket" ];
      after = [ "nix-daemon.socket" ];
      before = [ "systemd-user-sessions.service" ];
      unitConfig.RequiresMountsFor = homeManagerConfiguration.homeDirectory;
      serviceConfig.User = homeManagerConfiguration.username;
      serviceConfig.ExecStart =
        let
          systemctl = "XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/run/user/$UID} systemctl";
          sed = "${pkgs.gnused}/bin/sed";
          sessionVariables = lib.concatStringsSep "|" [
            "DBUS_SESSION_BUS_ADDRESS"
            "DISPLAY"
            "WAYLAND_DISPLAY"
            "XAUTHORITY"
            "XDG_RUNTIME_DIR"
          ];
        in
        pkgs.writeScript "hm-activate-${homeManagerConfiguration.username}" ''
          #! ${pkgs.runtimeShell} -el

          # A login shell runs the activation script, so that the
          # script gets the usual environment of the user. If the user
          # is logged in, the variables of the session are imported
          # too.
          eval "$(
            ${systemctl} --user show-environment 2> /dev/null \
            | ${sed} -En '/^(${sessionVariables})=/s/^/export /p'
          )"

          exec ${homeManagerConfiguration.activationPackage}/activate
        '';
    };

  # The unit for a user listed as declared elsewhere.
  userUnit =
    homeManagerConfiguration:
    lib.attrsets.recursiveUpdate (baseUnit homeManagerConfiguration) {
      wantedBy = [ "default.target" ];
      unitConfig = {
        ConditionUser = homeManagerConfiguration.username;
        RequiresMountsFor = "%h";
      };
      # A login shell runs the activation script, so that the script
      # gets the usual environment of the user, with Nix on the
      # search path.
      serviceConfig.ExecStart = pkgs.writeScript "hm-user-activate-${homeManagerConfiguration.username}" ''
        #! ${pkgs.runtimeShell} -el
        exec ${homeManagerConfiguration.activationPackage}/activate
      '';
    };

  unitsOf =
    mkUnit: selected:
    builtins.listToAttrs (
      builtins.map (homeManagerConfiguration: {
        name = unitName homeManagerConfiguration;
        value = mkUnit homeManagerConfiguration;
      }) selected
    );

  # The users that more than one home-manager configuration names.
  # Several home-manager configurations for the same user would each
  # write the home directory of that user.
  usernames = builtins.map (
    homeManagerConfiguration: homeManagerConfiguration.username
  ) homeManagerConfigurations;
  repeated = lib.lists.unique (
    builtins.filter (username: lib.lists.count (other: other == username) usernames > 1) usernames
  );
in
{
  # The core module of the class of this configuration, which declares
  # `config.caisson.exports.configurations`.
  imports = [ coreModule ];

  options.caisson.home-manager.activation.usersDeclaredElsewhere = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "chris" ];
    description = ''
      The users that have an account on the computers that run this
      configuration although `users.users` does not declare it.

      A NixOS configuration activates the home-manager configurations
      declared inside it. It expects the account of the user of each
      home-manager configuration in `users.users`, and it refuses a
      home-manager configuration whose user has no account there,
      because such a home-manager configuration is usually a mistake:
      a misspelled user name, or a home-manager configuration declared
      inside the wrong NixOS configuration.

      An account that systemd-homed manages is not in `users.users`.
      systemd-homed keeps the record of the account, and the NixOS
      configuration must not declare it a second time. List the user here. The
      home-manager configuration of a listed user is not refused. It
      is activated by a user unit that runs when the user logs in,
      which is when systemd-homed mounts the home directory.

      A user that is listed here and also declared in `users.users`
      is refused, because the two statements contradict each other.
    '';
  };

  # `optionalAttrs` and not `mkIf` decides whether the options are
  # defined at all. A definition under `mkIf false` is still a
  # definition, and NixOS refuses a definition of an option that no
  # module declares.
  config = lib.optionalAttrs hasUnits (
    lib.mkIf (!evalManifest.childless) (
      {
        assertions = [
          {
            assertion = withoutAccount == [ ];
            message = ''
              caisson: this ${integrationName} configuration has a home-manager configuration whose user has no account in `users.users`.
              ${lib.concatMapStringsSep "\n" (
                homeManagerConfiguration:
                "  the home-manager configuration `${homeManagerConfiguration.name}` is for the user `${homeManagerConfiguration.username}`"
              ) withoutAccount}
              Check `home.username` of the home-manager configuration, and that the home-manager configuration is declared inside the right ${integrationName} configuration.
              If something other than `users.users` provides the account, as systemd-homed does, add the user to `caisson.home-manager.activation.usersDeclaredElsewhere`.
            '';
          }
          {
            assertion = inBoth == [ ];
            message = ''
              caisson: `caisson.home-manager.activation.usersDeclaredElsewhere` lists a user that `users.users` also declares: ${lib.concatStringsSep ", " inBoth}.
              Remove the user from one of the two.
            '';
          }
          {
            assertion = !onSystemManager || installedHere == [ ];
            message = ''
              caisson: this system-manager configuration has a home-manager configuration that sets `caisson.useUserPackages`.
              ${lib.concatMapStringsSep "\n" (
                homeManagerConfiguration:
                "  the home-manager configuration `${homeManagerConfiguration.name}` for the user `${homeManagerConfiguration.username}`"
              ) installedHere}
              Only a NixOS configuration installs the packages of a home-manager configuration. Remove the setting, so that the activation of the home-manager configuration installs them.
            '';
          }
          {
            assertion = repeated == [ ];
            message = ''
              caisson: this ${integrationName} configuration activates more than one home-manager configuration for the same user.
              ${lib.concatMapStringsSep "\n" (
                username:
                "  ${username}: ${
                    lib.concatStringsSep ", " (
                      builtins.map (homeManagerConfiguration: homeManagerConfiguration.name) (
                        builtins.filter (
                          homeManagerConfiguration: homeManagerConfiguration.username == username
                        ) homeManagerConfigurations
                      )
                    )
                  }"
              ) repeated}
              Set a different `home.username` in one of them, or leave one out with `caisson.home-manager.exported`.
            '';
          }
        ];

        systemd.services = unitsOf systemUnit (builtins.filter isDeclared homeManagerConfigurations);
        systemd.user.services = unitsOf userUnit (
          builtins.filter (
            homeManagerConfiguration:
            !(isDeclared homeManagerConfiguration) && isElsewhere homeManagerConfiguration
          ) homeManagerConfigurations
        );
      }
      // lib.optionalAttrs hasUserPackages {
        # An account the NixOS configuration declares gets `home.path` among its
        # packages. A home-manager configuration whose user has no
        # account gets no entry here, so the assertion above names it.
        users.users = builtins.listToAttrs (
          builtins.map
            (homeManagerConfiguration: {
              name = homeManagerConfiguration.username;
              value.packages = [ homeManagerConfiguration.packages.holds ];
            })
            (
              builtins.filter (
                homeManagerConfiguration: declaredAccounts ? ${homeManagerConfiguration.username}
              ) installedHere
            )
        );
        environment.etc = builtins.listToAttrs (
          builtins.map
            (homeManagerConfiguration: {
              name = "profiles/per-user/${homeManagerConfiguration.username}";
              value.source = userEnvironment homeManagerConfiguration;
            })
            (
              builtins.filter (
                homeManagerConfiguration:
                !(declaredAccounts ? ${homeManagerConfiguration.username}) && isElsewhere homeManagerConfiguration
              ) installedHere
            )
        );
        # home-manager puts the file that sets the session variables of
        # the home-manager configuration in `etc/profile.d` of `home.path`.
        # Its `xsession` module reads the file from
        # `home.profileDirectory`, here `/etc/profiles/per-user/<user>`.
        # home-manager's NixOS module links the same directory.
        environment.pathsToLink = lib.mkIf (installedHere != [ ]) [ "/etc/profile.d" ];
      }
    )
  );
}
