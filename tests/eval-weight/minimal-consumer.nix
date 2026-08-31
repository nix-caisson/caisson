# SPDX-License-Identifier: MIT
# Eval-weight subject: the tests/integration/minimal-consumer flake (a
# trivial user of caisson) wired up hermetically from store paths and
# forced through its checks output. Compare against raw-flake-parts.nix
# (the same flake without caisson) to isolate framework overhead.
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
  caissonFlake = callFlake {
    src = caisson;
    inputs = {
      flake-parts = flakePartsFlake;
      nixpkgs-lib = nixpkgsLibFlake;
    };
  };

  minimalConsumer = callFlake {
    src = caisson + "/tests/integration/minimal-consumer";
    inputs = {
      # deps only exists for lock-level input sharing; the outputs do not use it.
      deps = { };
      parent = caissonFlake;
      nixpkgs = nixpkgsFlake;
      flake-parts = flakePartsFlake;
    };
  };
in
builtins.deepSeq (builtins.attrNames minimalConsumer.outputs)
  minimalConsumer.checks.${system}.minimal-consumer-success.drvPath
