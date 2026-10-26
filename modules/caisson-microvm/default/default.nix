# SPDX-License-Identifier: MIT
#
# The default module of the caisson-microvm class.
#
# The nearest NixOS configurations beneath a caisson-microvm
# configuration are its guests. This module adds caisson's NixOS module
# `microvm-guest`, which imports microvm.nix's guest module from the
# microvm.nix source of the caisson-microvm configuration, to the
# modules that such a NixOS configuration imports by default. A
# NixOS configuration declared inside a guest is no guest and does not
# get it. A guest that passes `moduleImports` selects its modules
# itself, and then it lists `microvm-guest` itself, as
# `caisson/microvm-guest` in a flake that lists caisson in `projects`.
#
# `closure-lib` is the library of caisson, where `microvm-guest` is
# registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The options under `caisson` are declared by the core module of the
  # class.
  imports = [ closure-lib.caisson.modules.caisson-microvm.core ];

  caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.microvm-guest
  ];
}
