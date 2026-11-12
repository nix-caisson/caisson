# SPDX-License-Identifier: MIT
#
# The core module of the structural class, forced into every
# structural configuration: the core module of caisson (the `generic`
# registry entry, reached through the closure) plus `perSystem`, the
# part of a structural configuration that is evaluated once for each
# system its children are evaluated for, and `allSystems`, the result
# of `perSystem` for each of those systems.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.core
    ./perSystem.nix
    ./allSystems.nix
  ];

  # A structural configuration has no single system, so it declares its
  # checks under `perSystem` (./perSystem.nix), which is evaluated once
  # for each system with the `pkgs` of that system in scope.
  disabledModules = [ { key = "caisson.checks.top-level"; } ];
}
