# SPDX-License-Identifier: MIT
#
# A home-manager module with which a home-manager configuration
# activates the profiles declared inside it: the configurations that
# are programs a person runs, such as an nvf or nixvim Neovim or a
# nemacs Emacs, each kept in a separate Nix profile, here a profile of
# the user, `$HOME/.local/state/caisson/profiles/<kind>/<name>`
# (`lib.caisson.integrations.profileOf`).
#
# A step of the activation of the home-manager configuration runs
# `activate` of each, after the files of the home-manager configuration
# are linked and the home-manager configuration has recorded what it
# applied. So `home-manager switch` puts each profile back to what the
# home-manager configuration declares, and so does the NixOS
# configuration above when it activates the home-manager configuration,
# at a switch of the NixOS configuration and at boot.
#
# The `bin` directory of each profile is added to `home.sessionPath`,
# by the path of the profile, so a switch of the profile changes the
# programs of every shell that starts afterwards. The `share/fonts`
# directory of each profile is a fontconfig directory, by the path of
# the profile, in a file of `~/.config/fontconfig/conf.d`, so the fonts
# of a profile are the fonts of the programs that start afterwards.
#
# caisson's `default` home-manager module imports this module. It
# defines nothing in the childless evaluation.
{ ... }:
{
  config,
  lib,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  profiles = selection.profilesActivatedBy evalManifest config.caisson.exports.configurations;
in
{
  config = lib.mkIf (!evalManifest.childless && profiles != [ ]) {
    home.activation.caissonProfiles =
      lib.hm.dag.entryAfter [ "linkGeneration" "caissonActivationMarker" ]
        (
          lib.concatMapStrings (entry: ''
            run ${entry.manifest.outputs.activationPackage}/activate
          '') profiles
        );

    home.sessionPath = builtins.map (entry: "${entry.manifest.outputs.profile.path}/bin") profiles;

    xdg.configFile."fontconfig/conf.d/60-caisson-profiles.conf".text = selection.profileFontsConfOf (
      builtins.map (entry: entry.manifest.outputs.profile.path) profiles
    );
  };
}
