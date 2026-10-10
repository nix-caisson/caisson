# SPDX-License-Identifier: MIT
#
# A stand-in for `nixos/modules/module-list.nix` of a nixpkgs source
# tree: the base module list `nixos/lib/eval-config.nix` defaults to
# and `lib.caisson.nixos.mkConfigurationFull` passes explicitly. The
# real list is the NixOS module tree, which is where `nixpkgs.pkgs`
# and the rest of the NixOS options are declared; this list declares
# `nixpkgs.pkgs`, so an evaluation carrying NixOS' nixpkgs module has
# the option that module defines, and an option a configuration reads
# to show the list reached the evaluation. It also declares the
# options of a machine that a home declared inside it is given: the
# accounts under `users.users`, and the Nix the machine runs.
[
  (
    { lib, ... }:
    {
      options = {
        nixpkgs.pkgs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        users.users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                home = lib.mkOption {
                  type = lib.types.str;
                };
                uid = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                };
              };
            }
          );
          default = { };
        };
        nix.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        nix.package = lib.mkOption {
          type = lib.types.str;
          default = "nix-of-the-machine";
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
