# SPDX-License-Identifier: MIT
#
# A NixOS module that imports the NixOS module of disko, for a NixOS
# configuration that writes its disk layout itself, as `disko.devices`,
# the way disko's NixOS form has it. The machine and its layout are then
# one configuration, and disko's tools read it as they read any NixOS
# configuration that imports disko's module: disko's command finds
# `config.disko.devices` and the scripts under `system.build`,
# `disko-install` replaces the disks with `extendModules`, and disko's
# image builder and install test extend the configuration.
#
# A NixOS configuration selects this module by name, as `disko`, or as
# `caisson/disko` in a flake that lists caisson in `projects`.
#
# The disko source is the one the composition declares or pins under
# the name `disko`, read from the library of the evaluation.
{ ... }:
{ lib, ... }:
let
  src =
    let
      found = lib.caisson-core.ecosystemSrc "disko";
    in
    if found == null then
      throw ''
        caisson's `disko` NixOS module needs the disko source.
        Declare `defaultEcosystemSrc.disko` in the mkLib call, or pin a
        source named `disko` in the `sources` passed to mkLib.
      ''
    else
      found;
in
{
  _file = "caisson:disko";
  imports = [ "${src}/module.nix" ];
}
