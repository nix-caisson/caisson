# SPDX-License-Identifier: MIT
/*
  A library overlay extends the composed `lib` with new attributes.

  Overlays registered via mkLibOverlay take the closure attrset
  ({ closure-inputs, mkLibOverlay, ... }) as their first arg list and
  return an { imports ? [ ], overlay } attrset: the standard Nix overlay
  signature (final: prev:) lives under `overlay`, and overlays this one
  depends on go under `imports`. Overlays are composed left-to-right
  during `mkLib`, imports first.

  Convention: namespace your additions (here `literate`) to avoid collisions
  with nixpkgs-lib and other overlays.
*/
{ ... }:
{
  imports = [ ];
  overlay = final: prev: {
    literate = (prev.literate or { }) // {
      greet = name: "Hello from literate-flake, ${name}!";
    };
  };
}
