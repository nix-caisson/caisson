# SPDX-License-Identifier: MIT
#
# A stand-in for `nixos/modules/module-list.nix` of a nixpkgs source
# tree: the base module list `nixos/lib/eval-config.nix` defaults to
# and `lib.caisson.nixos.mkConfigurationFull` passes explicitly. The
# real list is the NixOS module tree, which is where `nixpkgs.pkgs`
# and the rest of the NixOS options are declared; this one declares
# `nixpkgs.pkgs`, so an evaluation carrying NixOS' nixpkgs module has
# the option that module defines, and an option a configuration reads
# to show the list reached the evaluation.
[
  (
    { lib, ... }:
    {
      options = {
        nixpkgs.pkgs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        stub.fromBaseModules = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
      config.stub.fromBaseModules = true;
    }
  )
]
