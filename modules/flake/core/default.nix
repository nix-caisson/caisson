# SPDX-License-Identifier: MIT
#
# The flake class's core module, forced into every
# evaluation of the flake-parts integration: caisson's core
# module (the `generic` registry entry, reached through the closure)
# plus the mechanics of the class, the copies of `caisson.exports`
# into the flake outputs, the `systems` default and the checks under
# `perSystem`.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.core
    ./caisson
    ./perSystem.nix
  ];

  # A flake declares its checks under `perSystem` (./perSystem.nix),
  # which is evaluated once for each system with the `pkgs` of that
  # system in scope, and not at the top level of the options of the
  # flake, which has no single system.
  disabledModules = [ { key = "caisson.checks.top-level"; } ];
}
