# SPDX-License-Identifier: MIT
#
# The default module of the caisson-nixops4-resource class.
#
# It selects the NixOS adapter, registered as `nixos` in the class,
# which deploys the NixOS configuration declared beneath a resource.
# A resource that holds no NixOS configuration is not changed by it.
#
# NixOps4 runs `bin/apply` from the toplevel of the NixOS
# configuration it deploys. This module adds caisson's NixOS module
# `nixops4-apply`, which builds that script, to the modules that the
# nearest NixOS configurations beneath a resource import by default.
# It reaches a NixOS configuration inside a structural group or a disk
# layout beneath the resource. A NixOS configuration declared inside
# that one is not deployed by the resource and does not get it.
#
# A NixOS configuration that passes `moduleImports` selects its modules
# itself, and then it lists `nixops4-apply` itself, as
# `caisson/nixops4-apply` in a flake that lists caisson in `projects`.
#
# `closure-lib` is the library of caisson, where the adapter and
# `nixops4-apply` are registered under those names.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    # The option under `caisson.forNearestChildren` is declared by the
    # core module of the class.
    closure-lib.caisson.modules.caisson-nixops4-resource.core
    closure-lib.caisson.modules.caisson-nixops4-resource.nixos
  ];

  caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.nixops4-apply
  ];
}
