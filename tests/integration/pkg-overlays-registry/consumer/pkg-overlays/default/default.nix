# SPDX-License-Identifier: MIT
#
# The consumer's default entry imports the producer's shared entry, which
# the producer's default entry imports too, so a package set applying
# both defaults applies the shared entry once.
{ closure-lib, ... }:
{
  imports = [ closure-lib.caisson-core.libManifest.pkgOverlays."producer/shared" ];
  overlay = _final: _prev: {
    consumerDefault = "ok";
  };
}
