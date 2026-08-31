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
        caisson-nixpkgs = selfContained "caisson-nixpkgs";
        caisson-nixos = selfContained "caisson-nixos";
        caisson-home-manager = selfContained "caisson-home-manager";
        caisson-colmena = selfContained "caisson-colmena";
        caisson-terranix = selfContained "caisson-terranix";
        caisson-system-manager = selfContained "caisson-system-manager";
      };
    modules.flake.exported = modules: { inherit (modules) default; };

    lib.export.enabled = true;

  };

}
