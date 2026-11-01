# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  imports = [ ];
  overlay = final: prev: {
    middleChain = (prev.middleChain or { }) // {
      closure = {
        hasMiddleMarker = closure-lib.caisson.dependencies ? middleMarker;
        hasFinalMarker = closure-lib.caisson.dependencies ? finalMarker;
        hasCaisson = builtins.hasAttr "caisson" final;
      };
    };
  };
}
