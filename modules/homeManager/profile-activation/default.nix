# SPDX-License-Identifier: MIT
#
# A home-manager module with which a home activates the profiles
# declared inside it: the configurations that are programs a person
# runs, such as an nvf or nixvim Neovim, each kept in a Nix profile of
# its own, here a profile of the user,
# `$HOME/.local/state/caisson/profiles/<kind>/<name>`
# (`lib.caisson.integrations.profileOf`).
#
# A step of the activation of the home runs `activate` of each, after
# the files of the home are linked and the home has recorded what it
# applied. So `home-manager switch` puts each profile back to what the
# home declares, and so does the machine when it activates the home, at
# a switch of the machine and at boot.
#
# The home also installs the programs with which a shell chooses among
# profiles (`lib.caisson.integrations.profileShimsOf`), and sets the
# variable that chooses, `CAISSON_NVIM_PROFILE` for a Neovim, to the
# profile of the home, so that the programs the machine installs choose
# the same. A shell can `export` another value.
#
# caisson's `default` home-manager module imports this module. It
# defines nothing in the childless evaluation.
{ ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  profiles = selection.profilesActivatedBy evalManifest config.caisson.exports.configurations;

  choices = selection.profileChoicesOf {
    selected = config.caisson.profiles.selected;
    what = "this home";
  } profiles;
in
{
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
      profiles declared inside this home share a variable.
    '';
  };

  config = lib.mkIf (!evalManifest.childless && profiles != [ ]) {
    home.activation.caissonProfiles =
      lib.hm.dag.entryAfter [ "linkGeneration" "caissonActivationMarker" ]
        (
          lib.concatMapStrings (entry: ''
            run ${entry.manifest.outputs.activationPackage}/activate
          '') profiles
        );

    home.packages = lib.mapAttrsToList (
      variable: choice:
      selection.profileShimsOf {
        inherit pkgs variable;
        inherit (choice) programs;
        fallback = choice.chosen.manifest.outputs.profile.path;
      }
    ) choices;

    home.sessionVariables = builtins.mapAttrs (
      _variable: choice: choice.chosen.manifest.outputs.profile.path
    ) choices;
  };
}
