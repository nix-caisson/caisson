# SPDX-License-Identifier: MIT
#
# The configuration of the top of the registered world of the
# pinned-world suite, registered under the name of its composition. It
# declares a configuration of each integration whose module is
# registered under the configuration's name, and none of them is given
# a module, so each takes the module registered for it. The NixOS
# configuration `given-an-entry` is given the entry registered as
# `minimal` as its module, the way configurations that share one
# registered module take it.
{ ... }:
{ lib, ... }:
{
  caisson.nixos.configurations.registered = lib.caisson.nixos.mkConfiguration { };
  caisson.nixos.configurations.minimal = lib.caisson.nixos-minimal.mkConfiguration { };
  caisson.nixos.configurations.given-an-entry = lib.caisson.nixos-minimal.mkConfiguration {
    configModule = lib.caisson.configs.nixos.minimal;
  };
  caisson.home-manager.configurations.registered = lib.caisson.home-manager.mkConfiguration { };
  caisson.hjem.configurations.registered = lib.caisson.hjem.mkConfiguration { };
  caisson.structural.configurations.registered = lib.caisson.structural.mkConfiguration { };
  caisson.flake-parts.configurations.registered = lib.caisson.flake-parts.mkConfiguration { };
  caisson.caisson-colmena.configurations.registered = lib.caisson.caisson-colmena.mkConfiguration { };
  caisson.caisson-disko.configurations.registered = lib.caisson.caisson-disko.mkConfiguration { };
  caisson.disko.configurations.registered = lib.caisson.disko.mkConfiguration { };
  caisson.caisson-facter.configurations.registered = lib.caisson.caisson-facter.mkConfiguration { };
  caisson.facter.configurations.registered = lib.caisson.facter.mkConfiguration { };
  caisson.terranix.configurations.registered = lib.caisson.terranix.mkConfiguration { };
  caisson.system-manager.configurations.registered = lib.caisson.system-manager.mkConfiguration { };
  caisson.treefmt.configurations.registered = lib.caisson.treefmt.mkConfiguration { };
  caisson.nvf.configurations.registered = lib.caisson.nvf.mkConfiguration { };
  caisson.nixvim.configurations.registered = lib.caisson.nixvim.mkConfiguration { };
  caisson.topology.configurations.registered = lib.caisson.topology.mkConfiguration { };
  caisson.kubenix.configurations.registered = lib.caisson.kubenix.mkConfiguration { };
  caisson.nixidy.configurations.registered = lib.caisson.nixidy.mkConfiguration { };
}
