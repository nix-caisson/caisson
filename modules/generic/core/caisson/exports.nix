# SPDX-License-Identifier: MIT
#
# What the selectors chose: a top returns it, the flake-parts
# integration copies it into the flake outputs, and a parent passes
# it up. Each part is defined by the module that declares its
# selector, and a configuration that holds another beneath it merges
# the exports of the configuration beneath in as a further definition.
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.exports = {

    lib = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      description = "The part of the composed library `caisson.lib.exported` selected, merged with what lies beneath.";
    };

    libOverlays = lib.mkOption {
      type = lib.types.attrsOf types.libOverlay;
      description = "The registered library overlays `caisson.libOverlays.exported` selected, merged with what lies beneath.";
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.deferredModule);
      description = "Per class, the registered modules `caisson.modules.<class>.exported` selected, merged with what lies beneath.";
    };

    configurations = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      internal = true;
      description = ''
        The configurations declared beneath this configuration, at any
        depth, that it passes up: for each, its manifest and its path
        from here, a list of `{ type, name }` segments. A top names
        them from their paths and publishes each under the output
        attribute set its integration declares.
      '';
    };

    pkgOverlays = lib.mkOption {
      type = lib.types.attrsOf types.pkgOverlay;
      description = "The registered package overlays `caisson.pkgOverlays.exported` selected, merged with what lies beneath.";
    };

  };
}
