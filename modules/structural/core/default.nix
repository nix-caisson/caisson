# SPDX-License-Identifier: MIT
#
# The core module of the structural class, forced into every
# structural configuration: the options of caisson (the `generic`
# registry entry `caisson`, reached through the closure) plus
# `perSystem`, the part of a structural configuration that is evaluated
# once for each system its children are evaluated for, and
# `allSystems`, the result of `perSystem` for each of those systems.
# A structural configuration has no single system, so its checks are
# declared under `perSystem`, and the `generic` entry
# `top-level-checks` is not imported.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.caisson
    ./perSystem.nix
    ./allSystems.nix
  ];
}
