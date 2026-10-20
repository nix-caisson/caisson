# SPDX-License-Identifier: MIT
#
# A darwin module with which a macOS machine activates the
# home-manager configurations declared inside it.
#
# Activating a home-manager configuration means running the `activate`
# script of its activation package as the user of the home-manager
# configuration. home-manager has a nix-darwin module that does this
# for the home-manager configurations it embeds: a step of the
# machine's `postActivation` script runs `activate` for each
# home-manager configuration, as its user, through `launchctl asuser`
# and `sudo`. caisson does not use that nix-darwin module. A
# home-manager configuration declared inside a darwin configuration is
# a caisson configuration, and this module adds the same step, so that
# `darwin-rebuild switch` also applies the home-manager configurations.
#
# caisson's `default` darwin module imports this module. A darwin
# configuration that passes `moduleImports` selects its modules
# itself, and then its home-manager configurations are activated only
# if it lists this module.
#
# The module activates the home-manager configurations that this
# darwin configuration passes up, leaving out those declared inside a
# machine that is itself inside this one, and those evaluated for
# another system. It expects the machine to declare the account of the
# user of each home-manager configuration in `users.users`, as
# home-manager's nix-darwin module does. It refuses a home-manager
# configuration whose user has no account, and a home-manager
# configuration whose user's account sets no home directory.
#
# The step runs `activate` with no driver version, as caisson's NixOS
# activation does: the script also updates the home-manager profile of
# the user, so the user can run `home-manager switch` on the same
# profile. home-manager's nix-darwin module passes `--driver-version 1`,
# which leaves the profile alone.
#
# The module reads the home-manager configurations from the full
# evaluation of the darwin configuration, so in the childless
# evaluation it defines nothing.
{ closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;

  # True for an entry this machine activates. `entry.path` is the path
  # from this darwin configuration to the configuration of the entry, a
  # list of `{ type, name }` segments.
  isActivatedHere =
    entry:
    let
      above = lib.lists.init entry.path;
    in
    entry.manifest.type == "home-manager"
    && !(builtins.any (
      segment:
      builtins.elem segment.type [
        "nixos"
        "darwin"
        "system-manager"
      ]
    ) above)
    && entry.manifest.system == evalManifest.system;

  homes = builtins.map (entry: {
    # The name the home-manager configuration is published under, for
    # messages.
    name = entry.manifest.name;
    inherit (entry.value.config.home) username;
    inherit (entry.value) activationPackage;
  }) (builtins.filter isActivatedHere config.caisson.exports.configurations);

  withoutAccount = builtins.filter (home: !(config.users.users ? ${home.username})) homes;

  # nix-darwin leaves the home directory of an account at `null` until
  # the machine sets it, and a home-manager configuration needs one.
  withoutHomeDirectory = builtins.filter (
    home: config.users.users ? ${home.username} && config.users.users.${home.username}.home == null
  ) homes;

  usernames = builtins.map (home: home.username) homes;
  repeated = lib.lists.unique (
    builtins.filter (username: lib.lists.count (other: other == username) usernames > 1) usernames
  );

  # The step for a home-manager configuration: the step that the
  # nix-darwin module of home-manager writes, with `DRY_RUN` passed on
  # when the machine is activated dry.
  stepOf = home: ''
    echo Activating home-manager configuration for ${home.username} >&2
    hmDryRunArgs=()
    hmParentArgs="$(ps -p "$PPID" -ww -o args= || true)"
    if [[ -v DRY_RUN || "$hmParentArgs" == *" --dry-run"* ]]; then
      hmDryRunArgs=(env DRY_RUN=1)
    fi
    launchctl asuser "$(id -u ${home.username})" sudo -u ${home.username} --set-home "''${hmDryRunArgs[@]}" ${pkgs.writeShellScript "activation-${home.username}" ''
      exec ${home.activationPackage}/activate >&2
    ''}
  '';
in
{
  # The module reads `config.caisson.exports.configurations`. The core
  # module declares that option.
  imports = [ closure-lib.caisson.modules.darwin.core ];

  config = lib.mkIf (!evalManifest.childless && homes != [ ]) {
    assertions = [
      {
        assertion = withoutAccount == [ ];
        message = ''
          caisson: this darwin configuration has a home-manager configuration whose user has no account in `users.users`.
          ${lib.concatMapStringsSep "\n" (
            home: "  the home-manager configuration `${home.name}` is for the user `${home.username}`"
          ) withoutAccount}
          Declare the account in `users.users`, or check `home.username` of the home-manager configuration.
        '';
      }
      {
        assertion = withoutHomeDirectory == [ ];
        message = ''
          caisson: this darwin configuration has a home-manager configuration whose user's account sets no home directory.
          ${lib.concatMapStringsSep "\n" (
            home: "  the home-manager configuration `${home.name}` is for the user `${home.username}`"
          ) withoutHomeDirectory}
          Set `users.users.<user>.home`, which nix-darwin leaves at `null`.
        '';
      }
      {
        assertion = repeated == [ ];
        message = "caisson: this darwin configuration activates more than one home-manager configuration for ${lib.concatStringsSep ", " repeated}.";
      }
    ];

    system.activationScripts.postActivation.text = lib.concatMapStringsSep "\n" stepOf homes;
  };
}
