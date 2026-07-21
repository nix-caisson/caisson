# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{
  imports = [ ];
  overlay = final: prev: {
    middleChain = (prev.middleChain or { }) // {
      closure = {
        hasMiddleMarker = closure-inputs ? middleMarker;
        hasFinalMarker = closure-inputs ? finalMarker;
        hasCaisson = builtins.hasAttr "caisson" final;
      };
    };
  };
}
