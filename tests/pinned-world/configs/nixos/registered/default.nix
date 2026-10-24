# SPDX-License-Identifier: MIT
#
# A NixOS machine of the registered world, with a home-manager
# configuration declared inside it that takes its module from the
# registry as well.
{ ... }:
{ lib, ... }:
{
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
  };
  system.stateVersion = "25.05";
  users.users.registered = {
    isNormalUser = true;
    home = "/home/registered";
  };
  caisson.home-manager.configurations.registered = lib.caisson.home-manager.mkConfiguration { };
}
