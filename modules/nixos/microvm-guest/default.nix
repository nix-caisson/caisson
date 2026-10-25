# SPDX-License-Identifier: MIT
#
# A NixOS module for a guest of a caisson-microvm configuration: a
# NixOS configuration declared inside it. It imports microvm.nix's
# guest module, from the microvm.nix source the caisson-microvm
# configuration resolved, and defines the guest's microvm options from
# that configuration, read through
# `lib.caisson-core.evalManifest.nearest.caisson-microvm`:
#
# - `microvm.hypervisor`, `microvm.vcpu` and `microvm.mem` at
#   `mkDefault` priority, so the guest's own definition replaces them;
# - the definitions of `microvm.interfaces` and `microvm.shares` that
#   the caisson-microvm configuration holds, beside the guest's own;
# - for a guest that one of its slots declares, `microvm.vsock.cid` and
#   the shares of the slot.
#
# The default module of the caisson-microvm class adds this module to
# the nearest NixOS configurations beneath a caisson-microvm
# configuration. A guest that passes `moduleImports` selects its
# modules itself, and then it lists this module itself.
{ ... }:
{ lib, ... }:
let
  manifest = lib.caisson-core.evalManifest;

  machines =
    manifest.nearest.caisson-microvm or (throw ''
      caisson's `microvm-guest` NixOS module gives a guest the options of the
      caisson-microvm configuration it is declared inside, and this NixOS
      configuration is not declared inside a caisson-microvm configuration.
    '');

  inherit (machines.outputs) guests;

  # The slot of this guest, null for a guest no slot declares.
  slot = machines.outputs.slots.${manifest.name or ""} or null;
in
{
  _file = "caisson:microvm-guest";

  imports = [ "${machines.outputs.ecosystemSrc}/nixos-modules/microvm" ];

  microvm = {
    hypervisor = lib.mkDefault guests.hypervisor;
    vcpu = lib.mkDefault guests.vcpu;
    mem = lib.mkDefault guests.mem;
    interfaces = lib.mkMerge guests.interfaces;
    shares = lib.mkMerge (guests.shares ++ (if slot == null then [ ] else [ slot.shares ]));
  }
  // (if slot == null then { } else { vsock.cid = slot.cid; });
}
