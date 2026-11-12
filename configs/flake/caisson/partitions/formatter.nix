# SPDX-License-Identifier: MIT
{ lib, ... }:
{

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../../tests/dependencies).dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # Duplicated in configs/flake/checks, whose check of the
        # formatter uses the same settings: the partition and that
        # configuration are separate evaluations, so sharing the
        # settings would need more wiring than the duplication.
        perSystem.treefmt = {
          programs.nixfmt.enable = true;
        };
      };
  };

  partitionedAttrs.formatter = "formatter";

}
