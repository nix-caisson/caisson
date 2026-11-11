# SPDX-License-Identifier: MIT
#
# The checks a configuration declares, in an evaluation that builds
# for a single platform: a NixOS machine, a home-manager
# configuration, and any configuration declared inside such a
# configuration.
# The integration that builds the configuration records them in the
# `checks` of its manifest, beside the default checks of the
# integration, and the top gathers them under `checks.<system>` of
# its outputs. The flake class leaves this module out, because a
# flake-parts evaluation builds for every system of its `systems`.
# A flake declares its checks under `perSystem`, in the core module of
# the flake class.
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  key = "caisson.checks.single-system";

  options.caisson.checks = lib.mkOption {
    type = lib.types.attrsOf types.check;
    default = { };
    example = lib.literalExpression ''
      {
        toplevel.enable = false;
        debug-disabled = {
          derivation = pkgs.runCommand "debug-disabled" { } "touch $out";
          category = "eval";
          description = "the debug output is not published";
        };
      }
    '';
    description = ''
      The checks of this configuration, by name. An entry with a
      `derivation` declares a check, and it names its `category`. An
      entry without a `derivation` annotates the default check of the
      same name that the integration of the configuration declares: it
      can turn the check off with `enable = false`, give it another
      `description` or put it in another `category`. The check is
      gathered under `checks.<system>` of the top's outputs, for the
      system this configuration is evaluated for, under the names of
      the configurations from the top down to this configuration and the name of
      the check, joined with `-`.
    '';
  };
}
