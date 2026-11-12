# SPDX-License-Identifier: MIT
#
# The stages of the checks of a caisson top. A stage selects checks
# from the check record of the caisson top, and it says nothing about how to build them:
# a stage holds when every check it selects has been built.
{ lib, ... }:
let
  types = import ./types.nix { inherit lib; };
in
{
  options.caisson.checkStages = lib.mkOption {
    type = lib.types.attrsOf types.checkStage;
    default = { };
    example = lib.literalExpression ''
      {
        pull-request = {
          description = "the checks a pull request builds before it merges";
          select = entry: entry.category != "vm";
        };
      }
    '';
    description = ''
      The stages of the checks of this configuration, by name. Stages
      are declared at the caisson top, the configuration with no
      configuration above it: a caisson top that gathers checks refuses
      a stage declared in a configuration inside it. The manifest of the
      caisson top records each stage
      in `checkStages`.
    '';
  };
}
