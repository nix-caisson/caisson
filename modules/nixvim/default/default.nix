# SPDX-License-Identifier: MIT
#
# The `default` module of the `nixvim` class, imported by every
# configuration of the class unless it passes `moduleImports`: the
# `generic` registry entry `drift-warning`, reached through the closure.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.generic.drift-warning ];
}
