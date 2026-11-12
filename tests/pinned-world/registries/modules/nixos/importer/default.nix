# SPDX-License-Identifier: MIT
#
# A NixOS module that imports the registry entry
# `caisson/activation-marker` of the generic class and defines the option
# `caisson.importerNote`, which the file `option.nix` beside this file
# declares. `caisson/activation-marker` does not import `option.nix`.
# The registry gives the wrappers of `caisson/activation-marker` the
# file of this module, and this module defines the option in the same
# file. The check `registriesIgnoresTheDefinitionsOfTheModuleThatImportsAnEntry`
# of the pinned-world suite selects this module and reads that the
# check `registries` passes.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    ./option.nix
    closure-lib.caisson.modules.generic."caisson/activation-marker"
  ];
  caisson.importerNote = "a note of the importer module";
}
