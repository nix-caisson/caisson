# SPDX-License-Identifier: MIT
#
# The default module of the colmena class.
#
# The NixOS configurations declared inside a colmena configuration are
# its nodes, and colmena reads the `deployment` options back from each
# of them. This module adds caisson's NixOS module
# `colmena-deployment`, which declares those options, to the modules
# that a NixOS configuration declared inside this colmena
# configuration imports by default.
#
# A NixOS configuration that passes `moduleImports` selects its modules
# itself, and then it lists `colmena-deployment` itself, as
# `caisson/colmena-deployment` in a flake that lists caisson in
# `projects`.
#
# `closure-lib` is the library of caisson, where `colmena-deployment`
# is registered under that name.
{ closure-lib, ... }:
{ ... }:
{
  # The option under `caisson.forChildren` is declared by the core
  # module of the class.
  imports = [ closure-lib.caisson.modules.caisson-colmena.core ];

  caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.colmena-deployment
  ];
}
