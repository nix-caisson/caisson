# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration installed onto a disk layout
# of the upstream-compatible disko integration: a NixOS configuration
# declared inside a disko configuration. It imports disko's own NixOS
# module, from the disko source the layout was evaluated with, and
# defines `disko.devices` from the layout: the device tree as data,
# read from the layout through the manifest, at default priority.
#
# The NixOS configuration then holds what disko's tools read.
# disko's command finds `config.disko.devices` and builds the scripts
# under `system.build`; `disko-install` replaces the disks with
# `extendModules` and `mkVMOverride`, which wins over the default
# priority of this definition. The options disko's module declares
# beside `disko.devices`, such as `disko.imageBuilder` and
# `disko.tests`, are options of the NixOS configuration, set in its
# own modules.
#
# The default module of the disko class adds this module to every
# NixOS configuration declared inside a disko configuration. A NixOS
# configuration that passes `moduleImports` selects its modules itself,
# and then it lists this module itself.
{ ... }:
{ lib, ... }:
let
  layout =
    lib.caisson-core.evalManifest.nearest.disko or (throw ''
      caisson's `disko-layout` NixOS module gives a NixOS configuration the disk
      layout it is installed onto, and this NixOS configuration is not declared
      inside a disko configuration.
    '');
in
{
  _file = "caisson:disko-layout";

  imports = [ "${layout.outputs.ecosystemSrc}/module.nix" ];

  disko.devices = layout.outputs.serializableLayout;
}
