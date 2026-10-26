# SPDX-License-Identifier: MIT
#
# A NixOS module for a guest of a caisson-microvm configuration: a
# NixOS configuration declared inside it. It imports microvm.nix's
# guest module from the microvm.nix source the caisson-microvm
# configuration resolved, read through
# `lib.caisson-core.evalManifest.nearest.caisson-microvm`. The guest
# sets its `microvm.*` options in its own modules.
#
# The default module of the caisson-microvm class adds this module to
# the nearest NixOS configurations beneath a caisson-microvm
# configuration. A guest that passes `moduleImports` selects its
# modules itself, and then it lists this module itself.
{ ... }:
{ lib, ... }:
let
  machines =
    lib.caisson-core.evalManifest.nearest.caisson-microvm or (throw ''
      caisson's `microvm-guest` NixOS module imports microvm.nix's guest module from
      the source of the caisson-microvm configuration it is declared inside, and
      this NixOS configuration is not declared inside a caisson-microvm
      configuration.
    '');
in
{
  _file = "caisson:microvm-guest";

  imports = [ "${machines.outputs.ecosystemSrc}/nixos-modules/microvm" ];
}
