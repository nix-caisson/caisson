# SPDX-License-Identifier: MIT
{
  libOverlays,
  ...
}:

{ ... }:
{ config, lib, ... }:
{
  options.caisson.libOverlays = {

    export.enabled = lib.mkEnableOption "lib overlay export";
    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.attrsOf lib.caisson.types.libOverlay);
      description = ''
        Function that selects which registered library overlays to export as
        flake outputs. Receives the set of overlays registered via `mkLib`
        and returns the subset to publish under `flake.libOverlays`.
      '';
    };

  };

  config = {
    caisson.libOverlays = {
      export.enabled = lib.mkDefault true;
      exported = overlays: { };
    };

    flake.libOverlays =
      if config.caisson.libOverlays.export.enabled then
        config.caisson.libOverlays.exported libOverlays
      else
        { };

  };
}
