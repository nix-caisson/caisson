# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration installed onto a disk
# layout: a NixOS configuration declared inside a caisson-disko
# configuration. It gives the NixOS configuration the settings the
# layout's devices produce, `fileSystems`, `boot` and `swapDevices`,
# read from the layout through the manifest, at default priority.
#
# The default module of the caisson-disko class adds this module to
# every NixOS configuration declared inside a caisson-disko
# configuration. A NixOS configuration that passes `moduleImports`
# selects its modules itself, and then it lists this module itself.
#
# The NixOS configuration gets nothing of disko itself: no disko module
# and no `disko` option. The scripts that format and destroy the disks
# are outputs of the layout and are not reachable from the NixOS
# configuration. A module of the NixOS configuration that needs more of
# its layout reads it through
# `lib.caisson-core.evalManifest.nearest.caisson-disko`.
#
# The settings are copied under a fixed set of keys, since the module
# system needs the keys a module defines before it evaluates `config`.
# Those are the keys disko produces today. A layout that produces
# settings under any other key is refused rather than left out.
{ ... }:
{ lib, ... }:
let
  layout =
    lib.caisson-core.evalManifest.nearest.caisson-disko or (throw ''
      caisson's `caisson-disko-layout` NixOS module gives a NixOS configuration
      the settings of the disk layout it is installed onto, and this NixOS
      configuration is not declared inside a caisson-disko configuration.
    '');

  nixosConfig = layout.outputs.nixosConfig;

  copiedKeys = [
    "boot"
    "fileSystems"
    "swapDevices"
  ];

  copied =
    key: default:
    let
      others = builtins.attrNames (builtins.removeAttrs nixosConfig copiedKeys);
    in
    lib.throwIfNot (others == [ ]) ''
      The disk layout `${layout.name or "default"}` produces NixOS settings under
      ${builtins.concatStringsSep ", " others}, which caisson's `caisson-disko-layout`
      NixOS module does not copy into the NixOS configuration.
    '' (nixosConfig.${key} or default);
in
{
  _file = "caisson:caisson-disko-layout";

  fileSystems = copied "fileSystems" { };
  boot = copied "boot" { };
  swapDevices = copied "swapDevices" [ ];
}
