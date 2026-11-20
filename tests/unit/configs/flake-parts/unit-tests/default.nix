# SPDX-License-Identifier: MIT
{ ... }:
{ inputs, lib, ... }:
{
  imports = [
    inputs.nix-unit.modules.flake.default
  ];

  systems = [ "x86_64-linux" ];

  flake = {
    tests =
      import ../../../lib-overlays.nix {
        inherit inputs lib;
      }
      // {
        pins = import ../../../pins.nix {
          inherit lib;
          parent = inputs.parent.outPath;
        };
      };
  };

  perSystem =
    { system, ... }:
    {

      nix-unit = {
        inherit inputs;
      };

    };
}
