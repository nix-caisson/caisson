# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration that runs on the hardware of
# a facter configuration: a NixOS configuration declared inside one. It
# sets `hardware.facter.reportPath` to the report file of the facter
# configuration, at default priority, the line a NixOS configuration
# written for nixos-facter carries. nixpkgs' `hardware.facter` module
# reads the file and turns it into the NixOS settings of the hardware.
#
# The default module of the facter class adds this module to every
# NixOS configuration declared inside a facter configuration. A NixOS
# configuration that passes `moduleImports` selects its modules itself,
# and then it lists this module itself.
{ ... }:
{ lib, ... }:
let
  hardware =
    lib.caisson-core.evalManifest.nearest.facter or (throw ''
      caisson's `facter-hardware` NixOS module gives a NixOS configuration the
      facter report of the hardware it runs on, and this NixOS configuration is
      not declared inside a facter configuration.
    '');
in
{
  _file = "caisson:facter-hardware";

  hardware.facter.reportPath = lib.mkDefault hardware.outputs.reportPath;
}
