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
    # Opt in to exporting the composed library as a flake output. What
    # gets published is the namespace the composition declares on mkLib,
    # so `flake.lib` exposes `lib.literate-flake` (our overlay output).
    lib.export.enabled = true;
  };

  perSystem =
    { pkgs, ... }:
    {
      # Uses the composed library -- lib.literate-flake.greet comes from our overlay.
      packages.default = pkgs.writeText "literate-flake-demo" (lib.literate-flake.greet "Nix");
    };
}
