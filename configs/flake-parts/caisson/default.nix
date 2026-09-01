# SPDX-License-Identifier: MIT
{ ... }:
{ inputs, config, ... }:
{

  imports = [
    inputs.flake-parts.flakeModules.partitions
    ./partitions
  ];

  partitionedAttrs.checks = "checks";

  systems = [ "x86_64-linux" ];

  debug = false;

  caisson = {

    # Every registered overlay exports as-is: integrations carry no
    # hidden framework dependency (their machinery is baked in at
    # registration, and the registry comes from the consumer's
    # mkLib).
    libOverlays.exported = libOverlays: {
      inherit (libOverlays)
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
    modules.flake.exported = modules: { inherit (modules) default; };

    lib = {
      export.enabled = true;
      # The native surface mirrors the composed library's framework
      # namespaces, so flake-level and composed-level addresses match.
      exported = composedLib: { inherit (composedLib) caisson caisson-core; };
    };

  };

}
