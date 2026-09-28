# SPDX-License-Identifier: MIT
#
# An entry only the package sets that name it apply.
{ closure-lib, ... }:
{
  overlay = closure-lib.caisson.nixpkgs.mkPolyfillOverlay (_final: _prev: {
    polyfilledFlag = true;
  }) "nixpkgs-consumer";
}
