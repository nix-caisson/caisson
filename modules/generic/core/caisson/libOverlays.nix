# SPDX-License-Identifier: MIT
{ config, lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.libOverlays = {

    export.enabled = lib.mkEnableOption "lib overlay export";
    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.attrsOf types.libOverlay);
      description = ''
        Function that selects which registered library overlays to
        export. Receives the set of overlays registered via `mkLib` and
        returns the subset to publish.
      '';
    };

  };

  config = {
    caisson.libOverlays = {
      export.enabled = lib.mkDefault true;
      exported = overlays: { };
    };

    caisson.exports.libOverlays =
      if config.caisson.libOverlays.export.enabled then
        config.caisson.libOverlays.exported config.caisson.manifest.libOverlays
      else
        { };

  };
}
