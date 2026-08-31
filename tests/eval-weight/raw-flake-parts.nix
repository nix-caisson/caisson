# SPDX-License-Identifier: MIT
# Eval-weight control subject: the same trivial flake as
# tests/integration/minimal-consumer, but built with bare flake-parts and
# no caisson machinery. Subtracting this scenario from the
# minimal-consumer one isolates caisson's own overhead from the cost of
# flake-parts and nixpkgs, which would otherwise drown it out.
{
  caisson,
  flake-parts,
  nixpkgs,
  nixpkgs-lib,
  system,
}:
let
  callFlake = import (caisson + "/vendor/caisson-core/lib/kernel/call-flake.nix");

  nixpkgsLibFlake = callFlake { src = nixpkgs-lib; };
  flakePartsFlake = callFlake {
    src = flake-parts;
    inputs = {
      nixpkgs-lib = nixpkgsLibFlake;
    };
  };
  nixpkgsFlake = callFlake {
    src = nixpkgs;
    sourceInfo = {
      lastModified = 0;
      lastModifiedDate = "19700101000000";
    };
  };

  inputs = {
    inherit self;
    nixpkgs = nixpkgsFlake;
  };
  self = outputs // {
    inherit inputs;
    outPath = caisson + "/tests/eval-weight";
    _type = "flake";
  };
  outputs = flakePartsFlake.lib.mkFlake { inherit inputs; } {
    systems = [ system ];
    perSystem =
      { pkgs, ... }:
      {
        checks.minimal-consumer-success = pkgs.runCommand "minimal-consumer-success" { } ''
          echo 'minimal consumer composed successfully' > $out
        '';
      };
  };
in
builtins.deepSeq (builtins.attrNames outputs)
  outputs.checks.${system}.minimal-consumer-success.drvPath
