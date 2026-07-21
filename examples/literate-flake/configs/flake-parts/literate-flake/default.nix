# SPDX-License-Identifier: MIT
/*
  The config module is the flake's top-level configuration. It sets framework
  options and defines per-system outputs (packages, checks, devShells, etc.).

  This is separate from modules (which define reusable options/logic) --
  config is specific to this flake and not intended for re-export.
*/
{ ... }:
{ pkgs, lib, ... }:
{
  systems = [ "x86_64-linux" ];

  caisson = {
    # Identifies this flake in doc strings and as the lib export namespace.
    # With this set, `flake.lib` exposes `lib.literate` (our overlay output).
    configInfo.configName = "literate";

    # Opt in to exporting the composed library as a flake output.
    # Requires configName to be set.
    lib.export.enabled = true;
  };

  perSystem =
    { pkgs, ... }:
    {
      # Uses the composed library -- lib.literate.greet comes from our overlay.
      packages.default = pkgs.writeText "literate-demo" (lib.literate.greet "Nix");
    };
}
