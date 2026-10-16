# SPDX-License-Identifier: MIT
#
# The default module of the caisson-disko class.
#
# The NixOS configurations declared inside a disko configuration are
# installed onto its layout. This module adds caisson's NixOS module
# `caisson-disko-layout`, which gives a NixOS configuration the
# `fileSystems`, `boot` and `swapDevices` of the layout, to the modules
# that a NixOS configuration declared inside this disko configuration
# imports by default. A NixOS configuration that passes
# `moduleImports` selects its modules itself, and then it lists
# `caisson-disko-layout` itself, as `caisson/caisson-disko-layout` in a
# flake that lists caisson in `projects`.
#
# `closure-lib` is the library of caisson, where `caisson-disko-layout`
# is registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The options under `caisson` are declared by the core module of the
  # class.
  imports = [ closure-lib.caisson.modules.caisson-disko.core ];

  caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.caisson-disko-layout
  ];
}
