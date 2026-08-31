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

    libOverlays.exported =
      libOverlays:
      let
        # Integration overlays export with the framework overlay in their
        # import chain, so composing one from outside is self-contained.
        selfContained = name: {
          imports = [ libOverlays.default ];
          inherit (libOverlays.${name}) overlay;
        };
      in
      {
        inherit (libOverlays) default;
        nixpkgs = selfContained "nixpkgs";
        nixos = selfContained "nixos";
        home-manager = selfContained "home-manager";
        colmena = selfContained "colmena";
        terranix = selfContained "terranix";
        system-manager = selfContained "system-manager";
      };
    modules.flake.exported = modules: { inherit (modules) default; };

    lib.export.enabled = true;

  };

}
