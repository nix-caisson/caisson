# SPDX-License-Identifier: MIT
#
# A NixOS module that defines an option under `caisson` and imports a
# second copy of the core module of caisson for the nixos class. A
# project that pins another revision of caisson imports the core
# module from that revision: the module has the key that the registry
# gives the core module, and its files are in another store path. Here
# the module `copy.nix` beside this file stands for that copy, under
# the key of the module that the registry entry `caisson/core` imports.
# The module system evaluates the modules that share a key once, and
# caisson imports the core module into the NixOS configuration first,
# so `copy.nix` is not evaluated. The check
# `registriesFollowsTheKeyOfAModuleToItsDeclarations` of the
# pinned-world suite selects this module and reads that the check
# `registries` passes.
{ closure-lib, ... }:
{ ... }:
let
  # The module that the registry entry `caisson/core` imports, keyed
  # `registered.modules.nixos.core@caisson`.
  registered = builtins.head closure-lib.caisson.modules.nixos."caisson/core".imports;
in
{
  imports = [
    {
      inherit (registered) key;
      imports = [ ./copy.nix ];
    }
  ];
  caisson.structural.exportNote = "a note of the module that imports a copy of the core module";
}
