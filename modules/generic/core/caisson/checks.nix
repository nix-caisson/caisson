# SPDX-License-Identifier: MIT
#
# The checks a configuration declares, at the top level of its
# options: a NixOS configuration, a home-manager configuration, a
# structural configuration. The integration that builds the configuration
# records them in the `checks` of its manifest, beside the default
# checks of the integration, for each system the checks are built
# for, and the top gathers them under `checks.<system>` of its
# outputs. The flake class leaves this module out: a flake declares
# its checks under `perSystem`, in the core module of the flake class,
# where `perSystem` has the `pkgs` of each system of the flake. The
# `derivation` of a check is a function of `{ pkgs, pkgSets }`, which
# caisson calls once for each evaluation result of the configuration.
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  key = "caisson.checks.top-level";

  options.caisson.checks = lib.mkOption {
    type = lib.types.attrsOf types.check;
    default = { };
    example = lib.literalExpression ''
      {
        toplevel.enable = false;
        debug-disabled = {
          derivation = { pkgs, ... }: pkgs.runCommand "debug-disabled" { } "touch $out";
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
      `description` or put it in another `category`.

      A configuration has an evaluation result for each system it is
      evaluated for, and caisson calls the `derivation` of each check
      once for each evaluation result, with the package sets for that
      system. A NixOS configuration evaluated for x86_64-linux alone
      builds its checks for x86_64-linux. A structural configuration
      declared where x86_64-linux and aarch64-linux are listed builds
      its checks for both. A check is gathered under `checks.<system>` of
      the outputs of the top, for each system it is built for, under the
      names of the configurations from the top down to this
      configuration and the name of the check, joined with `-`.
    '';
  };
}
