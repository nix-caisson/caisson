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

  # A flake-parts evaluation builds for every system of its `systems`,
  # so a flake declares its checks under `perSystem` (./perSystem.nix)
  # and not at the top of the evaluation, where caisson's core module
  # declares them for an evaluation that builds for a single platform.
  disabledModules = [ { key = "caisson.checks.single-system"; } ];
}
