# SPDX-License-Identifier: MIT
#
# The caisson-microvm configuration `pool` of the microvm host test.
# It declares the guest `probe`, which takes the NixOS configuration
# registered as `configs/nixos/probe`.
{ ... }:
{ lib, ... }:
{
  caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration { };
}
