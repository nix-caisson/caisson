# SPDX-License-Identifier: MIT
#
# The core module of the `nixidy` class, forced into every
# configuration of the class: the options of caisson and the checks at
# the top level of its options (the `generic` registry entries
# `caisson` and `top-level-checks`, reached through the closure).
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.caisson
    closure-lib.caisson.modules.generic.top-level-checks
  ];
}
