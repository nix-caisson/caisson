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
        returns the subset to publish. Defaults to the overlays this
        composition registers itself: an entry a consumed project
        contributed (`<project>/<name>`) or caisson-core publishes into
        every composition leaves only when a selector names it.
      '';
    };

  };

  config = {
    caisson.libOverlays = {
      export.enabled = lib.mkDefault true;
      exported = lib.mkDefault (lib.filterAttrs (_: overlay: (overlay.project or null) == null));
    };

    caisson.exports.libOverlays =
      if config.caisson.libOverlays.export.enabled then
        config.caisson.libOverlays.exported config.caisson.manifest.libOverlays
      else
        { };

  };
}
