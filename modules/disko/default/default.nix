# SPDX-License-Identifier: MIT
#
# The default module of the disko class.
#
# A disko configuration is a disk layout on its own, as disko's
# standalone form has it. This module imports the core module of the
# class, which declares the options under `caisson`.
#
# `closure-lib` is the library of caisson, where the core module of the
# class is registered.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.disko.core ];
}
