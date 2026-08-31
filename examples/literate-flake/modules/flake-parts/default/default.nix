# SPDX-License-Identifier: MIT
/*
  A flake module defines options, config, and per-system outputs.

  Because mkFlake threads the composed `lib` as a special arg, modules
  receive the full library -- including overlays registered by this flake.
  Here we use `lib.literate-flake.greet` which was added by our library overlay.

  Modules registered via mkModule take the closure attrset
  ({ closure-inputs, closure-lib, mkModule, ... }) as their first arg list.
  This module does not use any of it, so it takes `{ ... }:`.
*/
{ ... }:
{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.greeting = pkgs.writeText "greeting" (lib.literate-flake.greet "world");
    };
}
