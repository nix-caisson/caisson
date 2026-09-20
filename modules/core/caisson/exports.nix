# SPDX-License-Identifier: MIT
#
# What the selectors chose, in one place: a top returns it, the
# flake-parts integration copies it into the flake outputs, and a
# parent passes it up. Each part is defined by the module that
# declares its selector.
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.exports = {

    lib = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      readOnly = true;
      description = "The part of the composed library `caisson.lib.exported` selected, or `{ }`.";
    };

    libOverlays = lib.mkOption {
      type = lib.types.attrsOf types.libOverlay;
      readOnly = true;
      description = "The registered library overlays `caisson.libOverlays.exported` selected, or `{ }`.";
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.deferredModule);
      readOnly = true;
      description = "Per class, the registered modules `caisson.modules.<class>.exported` selected.";
    };

  };
}
