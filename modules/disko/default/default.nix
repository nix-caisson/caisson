# SPDX-License-Identifier: MIT
#
# The default module of the disko class.
#
# A disko configuration is a disk layout on its own, as disko's
# standalone form has it, and gives the configurations declared inside
# it nothing. A NixOS configuration that carries its layout itself
# imports caisson's `disko` NixOS module, and a NixOS configuration
# installed onto a separate layout is declared inside a caisson-disko
# configuration.
#
# `closure-lib` is the library of caisson, where the core module of the
# class is registered.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.disko.core ];
}
