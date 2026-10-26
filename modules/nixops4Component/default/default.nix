# SPDX-License-Identifier: MIT
#
# The default module of the nixops4Component class, the class the
# nixops4 integration evaluates components with.
#
# It selects the module `nixos` of the class, which evaluates the
# `nixos.module` of a member that imports nixops4-nixos as a caisson
# NixOS configuration beneath the member.
#
# NixOps4 runs `bin/apply` from the toplevel of the NixOS
# configuration it deploys. This module adds caisson's NixOS module
# `nixops4-apply`, which builds that script, to the modules that the
# nearest NixOS configurations beneath a component import by default,
# as nixops4-nixos adds its `apply` module to the configuration it
# evaluates.
#
# `closure-lib` is the library of caisson, where these modules are
# registered under those names.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    # The option under `caisson.forNearestChildren` is declared by the
    # core module of the class.
    closure-lib.caisson.modules.nixops4Component.core
    closure-lib.caisson.modules.nixops4Component.nixos
  ];

  caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.nixops4-apply
  ];
}
