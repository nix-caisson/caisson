# SPDX-License-Identifier: MIT
#
# The categories of checks. Every check names a category, and a caisson top
# refuses a check it gathers when no configuration it gathers checks
# from declares the category of the check. caisson declares the categories its
# integrations use, and a configuration declares more, as an
# integration does with the `checkCategories` of
# `mkModuleConfiguration`.
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.checkCategories = lib.mkOption {
    type = lib.types.attrsOf types.checkCategory;
    default = { };
    example = lib.literalExpression ''
      {
        hardware = {
          description = "the machine boots on the hardware it is declared for";
          volatile = true;
        };
      }
    '';
    description = ''
      The categories of checks this configuration declares, by name.
      A category that the caisson top or any configuration inside it
      declares is declared for every check the caisson top gathers. A name that several
      configurations declare has the same `description` and `volatile`
      in each.
      caisson declares `build`, `eval`, `unit`, `vm` and `format`.
    '';
  };

  config.caisson.checkCategories = {
    build.description = "The artifact itself builds: a system closure, an activation package, a package.";
    eval.description = "An assertion on evaluation, as a derivation that builds nothing and fails when the assertion does.";
    unit.description = "The unit tests of Nix code pass, run with nix-unit.";
    vm.description = "A test that runs virtual machines with the NixOS test driver passes.";
    format.description = "The source files are formatted as the formatter configuration says.";
  };
}
