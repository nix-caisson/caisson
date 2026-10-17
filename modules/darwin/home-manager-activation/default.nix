# SPDX-License-Identifier: MIT
#
# A darwin module with which a macOS machine activates the homes
# declared inside it.
#
# Activating a home means running the `activate` script of its
# activation package as the user of the home. home-manager has a
# nix-darwin module that does this for the homes it embeds: a step of
# the machine's `postActivation` script runs `activate` for each home,
# as its user, through `launchctl asuser` and `sudo`. caisson does not
# use that nix-darwin module. A home declared inside a darwin
# configuration is a caisson configuration, and this module adds the
# same step, so that `darwin-rebuild switch` also applies the homes.
#
# caisson's `default` darwin module imports this module. A darwin
# configuration that passes `moduleImports` selects its modules
# itself, and then its homes are activated only if it lists this
# module.
#
# The module activates the home-manager configurations that this
# darwin configuration passes up, leaving out those declared inside a
# machine that is itself inside this one, and those evaluated for
# another system. It expects the machine to declare the account of the
# user of each home in `users.users`, as home-manager's nix-darwin
# module does, and refuses a home whose user has none.
#
# The step runs `activate` with no driver version, as caisson's NixOS
# activation does: the script also updates the home-manager profile of
# the user, so the user can run `home-manager switch` on the same
# profile. home-manager's nix-darwin module passes `--driver-version 1`,
# which leaves the profile alone.
#
# The module reads the homes from the full evaluation of the darwin
# configuration, so in the childless evaluation it defines nothing.
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
    # The name the home is published under, for messages.
    name = entry.manifest.name;
    inherit (entry.value.config.home) username;
    inherit (entry.value) activationPackage;
  }) (builtins.filter isActivatedHere config.caisson.exports.configurations);

  withoutAccount = builtins.filter (home: !(config.users.users ? ${home.username})) homes;

  usernames = builtins.map (home: home.username) homes;
  repeated = lib.lists.unique (
    builtins.filter (username: lib.lists.count (other: other == username) usernames > 1) usernames
  );

  # The step for one home: the step home-manager's nix-darwin module
  # writes, with `DRY_RUN` passed on when the machine is activated dry.
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
          caisson: this darwin configuration has a home whose user has no account in `users.users`.
          ${lib.concatMapStringsSep "\n" (
            home: "  the home `${home.name}` is for the user `${home.username}`"
          ) withoutAccount}
          Declare the account in `users.users`, or check `home.username` of the home.
        '';
      }
      {
        assertion = repeated == [ ];
        message = "caisson: this darwin configuration activates more than one home for ${lib.concatStringsSep ", " repeated}.";
      }
    ];

    system.activationScripts.postActivation.text = lib.concatMapStringsSep "\n" stepOf homes;
  };
}
