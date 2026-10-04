# SPDX-License-Identifier: MIT
#
# The flake outputs of what the selectors chose: `caisson.exports`
# copied into `flake.lib`, `flake.libOverlays`, `flake.modules` and,
# when the selection holds any, `flake.pkgOverlays`, with these
# flake-parts conventions on top: the `flake` class always exports a
# `default` entry (an empty module unless the selection provides it),
# so `flakeModules.default` exists for consumers that import it by
# convention, and `flake.flakeModules` mirrors `flake.modules.flake`.
#
# The configurations declared beneath the flake, at any depth, are
# published as well, each under the output attribute set its
# integration declares (`flake.nixosConfigurations`), named from its
# path: a name that is alone stays bare, and names that collide gain
# the segments that tell them apart.
{ config, lib, ... }:
let
  exports = config.caisson.exports;
in
{
  config = {
    flake =
      lib.caisson.integrations.publish exports.configurations
      // lib.optionalAttrs (exports.pkgOverlays != { }) {
        # The registered entries as they are, what a consumer's
        # `projects` merge reads; `overlays` carries them as plain
        # nixpkgs overlays.
        pkgOverlays = exports.pkgOverlays;
      }
      // {
        lib = exports.lib;
        libOverlays = exports.libOverlays;
        modules = exports.modules // {
          flake = {
            default = { };
          }
          // (exports.modules.flake or { });
        };
        flakeModules = config.flake.modules.flake;
      };
  };
}
