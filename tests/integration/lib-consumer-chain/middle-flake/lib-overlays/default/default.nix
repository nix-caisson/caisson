# SPDX-License-Identifier: MIT
{ closure-sources, ... }:
{
  imports = [ ];
  overlay = final: prev: {
    middleChain = (prev.middleChain or { }) // {
      closure = {
        hasMiddleMarker = closure-sources ? middleMarker;
        hasFinalMarker = closure-sources ? finalMarker;
        hasCaisson = builtins.hasAttr "caisson" final;
      };
    };
  };
}
