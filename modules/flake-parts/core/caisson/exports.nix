# SPDX-License-Identifier: MIT
#
# The flake outputs of what the selectors chose: `caisson.exports`
# copied into `flake.lib`, `flake.libOverlays` and `flake.modules`,
# with the two flake-parts conventions on top: the `flake` class
# always exports a `default` entry (an empty module unless the
# selection provides one), so `flakeModules.default` exists for
# consumers that import it by convention, and `flake.flakeModules`
# mirrors `flake.modules.flake`.
{ config, ... }:
let
  exports = config.caisson.exports;
in
{
  config = {
    flake.lib = exports.lib;
    flake.libOverlays = exports.libOverlays;
    flake.modules = exports.modules // {
      flake = {
        default = { };
      }
      // (exports.modules.flake or { });
    };
    flake.flakeModules = config.flake.modules.flake;
  };
}
