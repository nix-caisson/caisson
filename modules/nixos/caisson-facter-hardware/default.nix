# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration that runs on the hardware of
# a caisson-facter configuration: a NixOS configuration declared inside
# one. It hands the facter report of the hardware, checked by the
# caisson-facter configuration, to nixpkgs' `hardware.facter` module as
# `hardware.facter.report`, at default priority. nixpkgs' module turns
# the report into the NixOS settings of the hardware.
#
# The default module of the caisson-facter class adds this module to
# the nearest NixOS configurations beneath a caisson-facter
# configuration. A NixOS configuration that passes `moduleImports`
# selects its modules itself, and then it lists this module itself. A
# module of the NixOS configuration that needs more of its hardware
# reads it through `lib.caisson-core.evalManifest.nearest.caisson-facter`.
{ ... }:
{ lib, ... }:
let
  hardware =
    lib.caisson-core.evalManifest.nearest.caisson-facter or (throw ''
      caisson's `caisson-facter-hardware` NixOS module gives a NixOS configuration
      the facter report of the hardware it runs on, and this NixOS configuration
      is not declared inside a caisson-facter configuration.
    '');
in
{
  _file = "caisson:caisson-facter-hardware";

  hardware.facter.report = lib.mkDefault hardware.outputs.report;
}
