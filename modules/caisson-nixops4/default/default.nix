# SPDX-License-Identifier: MIT
#
# The default module of the caisson-nixops4 class.
#
# The nearest NixOS configurations beneath a nixops4 configuration are
# its machines, and NixOps4 runs `bin/apply` from the toplevel of each
# when it deploys it. This module adds caisson's NixOS module
# `nixops4-apply`, which builds that script, to the modules that such a
# NixOS configuration imports by default. It reaches the machines inside
# a structural group or a disk layout beneath the nixops4
# configuration. A NixOS configuration declared inside a machine is not
# a machine and does not get it.
#
# A NixOS configuration that passes `moduleImports` selects its modules
# itself, and then it lists `nixops4-apply` itself, as
# `caisson/nixops4-apply` in a flake that lists caisson in `projects`.
#
# `closure-lib` is the library of caisson, where `nixops4-apply` is
# registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The option under `caisson.forNearestChildren` is declared by the
  # core module of the class.
  imports = [ closure-lib.caisson.modules.caisson-nixops4.core ];

  caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.nixops4-apply
  ];
}
