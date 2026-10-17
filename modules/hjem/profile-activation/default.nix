# SPDX-License-Identifier: MIT
#
# An hjem module for the profiles declared inside an hjem configuration:
# the configurations that are programs a person runs, such as an nvf or
# nixvim Neovim, each kept in a profile of the user,
# `$HOME/.local/state/caisson/profiles/<kind>/<name>`
# (`lib.caisson.integrations.profileOf`).
#
# hjem's activation has no step a configuration can add, so the machine
# the hjem configuration is declared inside activates the profiles, as
# the user, after the hjem configuration is applied (the module
# `profile-activation` of the class of the machine). This module adds
# to the packages of the user the programs with which a shell chooses
# among profiles (`lib.caisson.integrations.profileShimsOf`), and sets
# the variable that chooses, `CAISSON_NVIM_PROFILE` for a Neovim, to the
# profile of the user, so that the programs the machine installs choose
# the same.
#
# caisson's `default` hjem module imports this module. It defines
# nothing in the childless evaluation.
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
    what = "this hjem configuration";
  } profiles;

  # The path of a profile, with `$HOME` written out as the directory of
  # the user, for a variable hjem writes as given.
  pathOf =
    choice:
    builtins.replaceStrings [ "$HOME" ] [ config.directory ]
      choice.chosen.manifest.outputs.profile.path;
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
      profiles declared inside this hjem configuration share a variable.
    '';
  };

  config = lib.mkIf (!evalManifest.childless && profiles != [ ]) {
    packages = lib.mapAttrsToList (
      variable: choice:
      selection.profileShimsOf {
        inherit pkgs variable;
        inherit (choice) programs;
        fallback = pathOf choice;
      }
    ) choices;

    environment.sessionVariables = builtins.mapAttrs (_variable: pathOf) choices;
  };
}
