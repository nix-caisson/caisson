# SPDX-License-Identifier: MIT
# This closes over the inputs to flake where this overlay is defined, i.e. caisson
{ closure-inputs, ... }:

{
  imports = [ ];
  overlay = final: prev: {

    flake-parts = (prev.flake-parts or { }) // closure-inputs.flake-parts.lib;

  };
}
