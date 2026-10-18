# SPDX-License-Identifier: MIT
#
# A darwin module with which a macOS machine activates the profiles
# declared inside it, as the NixOS module `profile-activation` does for a
# NixOS machine: see there.
#
# A step of the machine's `postActivation` script runs `activate` of
# each profile of the system as root, and of each profile declared
# inside a hjem configuration inside the machine as its user, through
# `launchctl asuser` and `sudo`, after the hjem agents are restarted. A
# profile inside a home is activated by the home. The machine installs
# the programs that choose among the profiles of the system in
# `environment.systemPackages`.
#
# caisson's `default` darwin module imports this module. It defines
# nothing in the childless evaluation.
{ closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  exported = config.caisson.exports.configurations;

  ofSystem = selection.profilesActivatedBy evalManifest exported;

  hjemUsers =
    builtins.map
      (entry: {
        inherit (entry.manifest.value.config) user;
        profiles = selection.profilesActivatedBy entry.manifest exported;
      })
      (
        builtins.filter (
          entry: entry.manifest.type == "hjem" && selection.checksMarkerOf evalManifest entry
        ) exported
      );

  asRoot = entry: ''
    ${entry.manifest.outputs.activationPackage}/activate
  '';

  asUser = user: entry: ''
    launchctl asuser "$(id -u ${lib.escapeShellArg user})" sudo -u ${lib.escapeShellArg user} --set-home ${entry.manifest.outputs.activationPackage}/activate
  '';

  choices = selection.profileChoicesOf {
    selected = config.caisson.profiles.selected;
    what = "this machine";
  } ofSystem;

  shims = lib.mapAttrsToList (
    variable: choice:
    selection.profileShimsOf {
      inherit pkgs variable;
      inherit (choice) programs;
      fallback = choice.chosen.manifest.outputs.profile.path;
    }
  ) choices;

  steps =
    builtins.map asRoot ofSystem
    ++ builtins.concatMap (hjem: builtins.map (asUser hjem.user) hjem.profiles) hjemUsers;
in
{
  imports = [ closure-lib.caisson.modules.darwin.core ];

  options.caisson.profiles.selected = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      CAISSON_NVIM_PROFILE = "nvf/editor";
    };
    description = ''
      By the variable that chooses among them, the profile a shell runs
      when it sets no other, as `<kind>/<name>`: `nvf/editor` is the nvf
      configuration declared as `editor`. Needed only where several
      profiles declared inside this configuration share a variable.
    '';
  };

  config = lib.mkIf (!evalManifest.childless && steps != [ ]) {
    system.activationScripts.postActivation.text = lib.mkAfter (lib.concatStrings steps);
    environment.systemPackages = shims;
  };
}
