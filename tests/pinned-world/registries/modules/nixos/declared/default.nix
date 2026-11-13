# SPDX-License-Identifier: MIT
#
# A NixOS module that defines an option under `caisson` and imports
# the core module of caisson for the nixos class, which declares the
# option. A flake that lists caisson in `projects` reads that module
# from the registry as `caisson/core`. The check `registries` of a
# caisson top whose NixOS configuration selects this module passes.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.nixos."caisson/core" ];
  caisson.structural.exportNote = "a note of the declared module";
}
