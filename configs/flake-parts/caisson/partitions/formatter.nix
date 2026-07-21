# SPDX-License-Identifier: MIT
{ lib, ... }:
{

  partitions.formatter = {
    extraInputs = lib.caisson.partitionExtraInputs ../../../../tests/dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # Duplicated in checks.nix — partitions evaluate independently,
        # so sharing would require more boilerplate than the duplication.
        perSystem.treefmt = {
          programs.nixfmt.enable = true;
          # Vendored upstream code keeps upstream formatting so the
          # local patch delta stays reviewable against its source.
          settings.global.excludes = [ "vendor/*" ];
        };
      };
  };

  partitionedAttrs.formatter = "formatter";

}
