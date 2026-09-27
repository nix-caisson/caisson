# SPDX-License-Identifier: MIT
#
# The project's default entry: what a consumer's package sets apply
# without naming it. It imports the shared entry from the registry of
# the composition that registered it.
{ closure-lib, ... }:
{
  imports = [ closure-lib.caisson-core.libManifest.pkgOverlays.shared ];
  overlay = _final: _prev: {
    producerDefault = "ok";
  };
}
