# SPDX-License-Identifier: MIT
#
# What caisson exports: every registered overlay and flake module, and
# the composed library's framework namespaces. A plain module of the
# core module's options, so the structural top takes it as its
# configuration and the flake top's configuration imports it.
{ ... }:
{

  caisson = {

    configInfo.configName = "caisson";

    # Every registered overlay exports as-is: integrations carry no
    # hidden framework dependency (their machinery is baked in at
    # registration, and the registry comes from the consumer's
    # mkLib).
    libOverlays.exported = libOverlays: {
      inherit (libOverlays)
        structural
        flake-parts
        tooling
        nixpkgs
        nixos
        home-manager
        colmena
        terranix
        system-manager
        ;
    };
    modules.flake.exported = modules: {
      inherit (modules)
        default
        nixpkgs
        nixpkgs-interface
        ;
    };

    lib = {
      export.enabled = true;
      # The native surface mirrors the composed library's framework
      # namespaces, so flake-level and composed-level addresses match.
      exported = lib: { inherit (lib) caisson caisson-core; };
    };

  };

}
