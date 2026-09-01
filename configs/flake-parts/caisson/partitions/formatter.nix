# SPDX-License-Identifier: MIT
{ lib, ... }:
{

  partitions.formatter = {
    extraInputs = lib.caisson-core.partitionExtraInputs ../../../../tests/dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # Duplicated in checks.nix: partitions evaluate independently,
        # so sharing would require more boilerplate than the duplication.
        perSystem.treefmt = {
          programs.nixfmt.enable = true;
        };
      };
  };

  partitionedAttrs.formatter = "formatter";

}
