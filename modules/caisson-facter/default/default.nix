# SPDX-License-Identifier: MIT
#
# The default module of the caisson-facter class.
#
# The NixOS configurations declared inside a facter configuration run
# on its hardware. This module adds caisson's NixOS module
# `caisson-facter-hardware`, which hands the facter report to nixpkgs'
# `hardware.facter` module, to the modules that a NixOS configuration
# declared inside this facter configuration imports by default. A
# NixOS configuration that passes `moduleImports` selects its modules
# itself, and then it lists `caisson-facter-hardware` itself, as
# `caisson/caisson-facter-hardware` in a flake that lists caisson in
# `projects`.
#
# `closure-lib` is the library of caisson, where
# `caisson-facter-hardware` is registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The options under `caisson` are declared by the core module of the
  # class.
  imports = [ closure-lib.caisson.modules.caisson-facter.core ];

  caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.caisson-facter-hardware
  ];
}
