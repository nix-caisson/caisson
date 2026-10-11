# SPDX-License-Identifier: MIT
#
# A NixOS module with which a machine activates the homes declared
# inside it.
#
# Activating a home means running the `activate` script of its
# activation package as the user of the home. The script links the
# files of the home into the home directory and installs its
# packages. home-manager has a NixOS module that does this for the
# homes it embeds. caisson does not use that NixOS module. A home
# declared inside a NixOS configuration is a caisson configuration,
# and this module writes the systemd units that activate it, so that
# switching the machine to a new generation also applies its homes.
#
# caisson's `default` NixOS module imports this module. A NixOS
# configuration that passes `moduleImports` selects its modules
# itself, and then its homes are activated only if it lists this
# module.
#
# Which homes
#
# The module activates the home-manager configurations that this
# NixOS configuration passes up: the homes declared inside it, also
# through a structural configuration, that its
# `caisson.home-manager.exported` selector selects. It leaves out two
# kinds. A home declared inside a NixOS configuration that is itself
# inside this one belongs to that inner machine. A home evaluated for
# a system other than the system of this machine cannot run here.
#
# Which unit
#
# The module expects the machine to declare the account of the user
# of each home in `users.users`. For such an account, the unit is a
# system unit named `home-manager-<user>`. It runs as that user during
# boot, before users can log in. This is the unit home-manager's NixOS
# module writes.
#
# A home whose user has no account in `users.users` is refused, with
# an assertion that names the home and the user. On most machines such
# a home is a mistake: a misspelled user name, or a home declared on
# the wrong machine.
#
# Some accounts are provided by something other than `users.users`. An
# account that systemd-homed manages is one. The machine must not
# declare such an account, because systemd-homed keeps the record of
# it, and its home directory is mounted only at login. The option
# `caisson.home-manager.activation.usersDeclaredElsewhere` lists the
# users that have such an account on this machine.
#
# For a user in that list, the unit is a user unit named
# `home-manager-<user>`, with `ConditionUser=<user>`. It runs when the
# service manager of that user starts, which is at login.
#
# The profile of the home
#
# Both units run `activate` with no driver version, which is what
# home-manager calls the legacy behavior: the script also updates the
# home-manager profile of the user. The user can then run
# `home-manager switch` and `home-manager generations` on the same
# profile. home-manager's NixOS module passes `--driver-version 1`,
# which leaves the profile alone.
#
# The module reads the homes from the full evaluation of the NixOS
# configuration. The childless evaluation leaves out the
# configurations declared inside the NixOS configuration, so there the
# module defines nothing.
#
# The nixos-minimal integration evaluates NixOS with a module list
# that has no systemd options and no assertions. A NixOS configuration
# of that kind cannot run units, so there the module also defines
# nothing.
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

  # True when this evaluation declares the options the module defines.
  hasUnits =
    options ? assertions
    && options ? systemd
    && options.systemd ? services
    && options.systemd ? user
    && options ? users;

  # True for an entry this machine activates. `entry.path` is the path
  # from this NixOS configuration to the configuration of the entry, a
  # list of `{ type, name }` segments.
  isActivatedHere =
    entry:
    let
      above = lib.lists.init entry.path;
    in
    entry.manifest.type == "home-manager"
    # A NixOS configuration on the path is a machine inside this
    # machine, and the home belongs to it.
    && !(builtins.any (segment: segment.type == "nixos") above)
    && entry.manifest.system == evalManifest.system;

  # What the units need of each home.
  homes = builtins.map (entry: {
    # The name the home is published under, for messages.
    name = entry.manifest.name;
    inherit (entry.value.config.home) username homeDirectory;
    inherit (entry.value) activationPackage;
  }) (builtins.filter isActivatedHere config.caisson.exports.configurations);

  # True when the machine declares the account of the user of the home
  # in `users.users`.
  isDeclared = home: config.users.users ? ${home.username};

  # The users that have an account on this machine although
  # `users.users` does not declare it.
  elsewhere = config.caisson.home-manager.activation.usersDeclaredElsewhere;
  isElsewhere = home: builtins.elem home.username elsewhere;

  # The homes whose user has no account the machine knows of: not in
  # `users.users`, and not listed as declared elsewhere. The module
  # refuses these.
  withoutAccount = builtins.filter (home: !(isDeclared home) && !(isElsewhere home)) homes;

  # The users that are listed as declared elsewhere and are also in
  # `users.users`. The two statements contradict each other.
  inBoth = builtins.filter (username: config.users.users ? ${username}) elsewhere;

  unitName = home: "home-manager-${utils.escapeSystemdPath home.username}";

  # The settings both kinds of unit share. They are the settings of
  # the unit home-manager's NixOS module writes.
  baseUnit = home: {
    description = "Home Manager environment for ${home.username}";
    # The unit is not stopped when its definition changes. The new
    # generation of the machine starts it again, which activates the
    # new generation of the home.
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
      SyslogIdentifier = "hm-activate-${home.username}";
    };
  };

  # The unit for an account the machine declares.
  systemUnit =
    home:
    lib.attrsets.recursiveUpdate (baseUnit home) {
      wantedBy = [ "multi-user.target" ];
      wants = [ "nix-daemon.socket" ];
      after = [ "nix-daemon.socket" ];
      before = [ "systemd-user-sessions.service" ];
      unitConfig.RequiresMountsFor = home.homeDirectory;
      serviceConfig.User = home.username;
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
        pkgs.writeScript "hm-activate-${home.username}" ''
          #! ${pkgs.runtimeShell} -el

          # A login shell runs the activation script, so that the
          # script gets the usual environment of the user. If the user
          # is logged in, the variables of the session are imported
          # too.
          eval "$(
            ${systemctl} --user show-environment 2> /dev/null \
            | ${sed} -En '/^(${sessionVariables})=/s/^/export /p'
          )"

          exec ${home.activationPackage}/activate
        '';
    };

  # The unit for a user listed as declared elsewhere.
  userUnit =
    home:
    lib.attrsets.recursiveUpdate (baseUnit home) {
      wantedBy = [ "default.target" ];
      unitConfig = {
        ConditionUser = home.username;
        RequiresMountsFor = "%h";
      };
      # A login shell runs the activation script, so that the script
      # gets the usual environment of the user, with Nix on the
      # search path.
      serviceConfig.ExecStart = pkgs.writeScript "hm-user-activate-${home.username}" ''
        #! ${pkgs.runtimeShell} -el
        exec ${home.activationPackage}/activate
      '';
    };

  unitsOf =
    mkUnit: selected:
    builtins.listToAttrs (
      builtins.map (home: {
        name = unitName home;
        value = mkUnit home;
      }) selected
    );

  # The users that more than one home names. Two homes for one user
  # would both write the home directory of that user.
  usernames = builtins.map (home: home.username) homes;
  repeated = lib.lists.unique (
    builtins.filter (username: lib.lists.count (other: other == username) usernames > 1) usernames
  );
in
{
  # The module reads `config.caisson.exports.configurations`. The core
  # module declares that option.
  imports = [ closure-lib.caisson-core.modules.nixos.core ];

  options.caisson.home-manager.activation.usersDeclaredElsewhere = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "chris" ];
    description = ''
      The users that have an account on this machine although
      `users.users` does not declare it.

      A NixOS configuration activates the homes declared inside it.
      It expects the account of the user of each home in
      `users.users`, and it refuses a home whose user has no account
      there, because such a home is usually a mistake: a misspelled
      user name, or a home declared on the wrong machine.

      An account that systemd-homed manages is not in `users.users`.
      systemd-homed keeps the record of the account, and the machine
      must not declare it a second time. List the user here. The home
      of a listed user is not refused. It is activated by a user unit
      that runs when the user logs in, which is when systemd-homed
      mounts the home directory.

      A user that is listed here and also declared in `users.users`
      is refused, because the two statements contradict each other.
    '';
  };

  # `optionalAttrs` and not `mkIf` decides whether the options are
  # defined at all. A definition under `mkIf false` is still a
  # definition, and NixOS refuses a definition of an option that no
  # module declares.
  config = lib.optionalAttrs hasUnits (
    lib.mkIf (!evalManifest.childless) {
      assertions = [
        {
          assertion = withoutAccount == [ ];
          message = ''
            caisson: this NixOS configuration has a home whose user has no account in `users.users`.
            ${lib.concatMapStringsSep "\n" (
              home: "  the home `${home.name}` is for the user `${home.username}`"
            ) withoutAccount}
            Check `home.username` of the home, and that the home is declared inside the right NixOS configuration.
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
          assertion = repeated == [ ];
          message = ''
            caisson: this NixOS configuration activates more than one home for the same user.
            ${lib.concatMapStringsSep "\n" (
              username:
              "  ${username}: ${
                  lib.concatStringsSep ", " (
                    builtins.map (home: home.name) (builtins.filter (home: home.username == username) homes)
                  )
                }"
            ) repeated}
            Set a different `home.username` in one of them, or leave one out with `caisson.home-manager.exported`.
          '';
        }
      ];

      systemd.services = unitsOf systemUnit (builtins.filter isDeclared homes);
      systemd.user.services = unitsOf userUnit (
        builtins.filter (home: !(isDeclared home) && isElsewhere home) homes
      );
    }
  );
}
