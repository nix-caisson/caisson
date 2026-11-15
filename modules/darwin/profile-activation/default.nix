# SPDX-License-Identifier: MIT
#
# A darwin module with which a nix-darwin configuration activates the
# profiles declared inside it, as the NixOS module `profile-activation`
# does for a NixOS configuration: see there.
#
# A step of the `postActivation` script of the nix-darwin configuration
# runs `activate` of each profile of the system as root, and of each
# profile declared inside a hjem configuration inside the nix-darwin
# configuration as its user, through `launchctl asuser` and `sudo`,
# after the hjem agents are restarted. A profile inside a home-manager
# configuration is activated by the home-manager configuration. The
# `bin` directory of each profile of the system is put on the `PATH` of
# every shell, in `environment.profiles`.
#
# caisson's `default` darwin module imports this module. It defines
# nothing in the childless evaluation.
{ closure-lib, ... }:
{
  config,
  lib,
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

  steps =
    builtins.map asRoot ofSystem
    ++ builtins.concatMap (hjem: builtins.map (asUser hjem.user) hjem.profiles) hjemUsers;
in
{
  imports = [ closure-lib.caisson.modules.darwin.core ];

  config = lib.mkIf (!evalManifest.childless && steps != [ ]) {
    system.activationScripts.postActivation.text = lib.mkAfter (lib.concatStrings steps);
    environment.profiles = builtins.map (entry: entry.manifest.outputs.profile.path) ofSystem;
  };
}
