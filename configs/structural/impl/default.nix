# SPDX-License-Identifier: MIT
#
# What caisson exports: every registered overlay and module, and the
# composed library's framework namespaces. Both tops evaluate this
# configuration beneath themselves and merge in what it exports.
{ ... }:
{ ... }:
{

  caisson = {

    configInfo.configName = "caisson";

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
        home-manager
        home-manager-minimal
        colmena
        terranix
        system-manager
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
          nixpkgs-interface
          ;
      };
      generic.exported = modules: { inherit (modules) core; };
      structural.exported = modules: { inherit (modules) core; };
    };

    lib = {
      export.enabled = true;
      # The native surface mirrors the composed library's framework
      # namespaces, so flake-level and composed-level addresses match.
      exported = lib: { inherit (lib) caisson caisson-core; };
    };

  };

}
