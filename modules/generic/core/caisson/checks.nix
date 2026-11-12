# SPDX-License-Identifier: MIT
#
# The checks a configuration declares at the top level of its
# options, in a class whose evaluation result has a system: a NixOS
# configuration, a home-manager configuration. Such a configuration
# has an evaluation result for each system it is evaluated for, and
# each evaluation result declares its checks with the `pkgs` of its
# system in scope. The integration records them in the `checks` of the
# manifest, beside the default checks of the integration, and the
# caisson top gathers them under `checks.<system>` of its outputs.
#
# The structural and flake classes leave this module out: their
# evaluation result has no single system, and they declare checks
# under `perSystem`, which is evaluated once for each system.
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
          derivation = pkgs.runCommand "debug-disabled" { } "touch $out";
          category = "eval";
          description = "the debug output is not published";
        };
      }
    '';
    description = ''
      The checks of this evaluation result, by name, for its system. An
      entry with a `derivation` declares a check, and it names its
      `category`. An entry without a `derivation` annotates the default
      check of the same name that the integration of the configuration
      declares: it can turn the check off with `enable = false`, give it
      another `description` or put it in another `category`. A check is
      gathered under `checks.<system>` of the outputs of the caisson
      top, under the names of the configurations from the caisson top
      down to this
      configuration and the name of the check, joined with `-`.
    '';
  };
}
