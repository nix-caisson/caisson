# SPDX-License-Identifier: MIT
#
# What caisson exports: every registered overlay and module, and the
# composed library's framework namespaces. The flake-parts caisson top
# and the structural caisson top declare this configuration inside
# themselves and
# merge in what it exports.
{ ... }:
{ ... }:
{

  caisson = {

    # Every registered overlay exports as-is: its machinery is baked in
    # at registration, and the registry comes from the mkLib call of
    # the consumer.
    libOverlays.exported = libOverlays: {
      inherit (libOverlays)
        integrations
        structural
        flake-parts
        tooling
        nixpkgs
        nixos
        nixos-minimal
        nixos-test
        home-manager
        home-manager-minimal
        hjem
        caisson-colmena
        colmena
        caisson-disko
        disko
        caisson-facter
        facter
        darwin
        terranix
        system-manager
        treefmt
        nvf
        nixvim
        nemacs
        topology
        kubenix
        nixidy
        ;
    };

    # Every registered module exports as-is, the `core` of each class
    # among them: a consumer's composition then carries `caisson/core`
    # in that class, which its integration forces like any `core`.
    modules = {
      flake.exported = modules: {
        inherit (modules)
          core
          default
          nixpkgs
          ;
      };
      structural.exported = modules: { inherit (modules) core; };
    };

  };

}
