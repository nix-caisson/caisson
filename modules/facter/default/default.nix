# SPDX-License-Identifier: MIT
#
# The default module of the facter class.
#
# The nearest NixOS configurations beneath a facter configuration run
# on its hardware. This module adds caisson's NixOS module
# `facter-hardware`, which sets `hardware.facter.reportPath` to the
# report file, to the modules that such a NixOS configuration imports
# by default. A NixOS configuration declared inside one of those
# machines, such as an image or a guest, does not run on that hardware
# and does not get it. A NixOS configuration that passes
# `moduleImports` selects its modules itself, and then it lists
# `facter-hardware` itself, as `caisson/facter-hardware` in a flake
# that lists caisson in `projects`.
#
# `closure-lib` is the library of caisson, where `facter-hardware` is
# registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The options under `caisson` are declared by the core module of the
  # class.
  imports = [ closure-lib.caisson.modules.facter.core ];

  caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.facter-hardware
  ];
}
