# SPDX-License-Identifier: MIT
#
# A stand-in for `modules/modules.nix` of the home-manager source: the
# module list the evaluation imports, with that file's signature
# (`{ pkgs, lib, check ? true, useNixpkgsModule ? true, minimal ? false }`)
# and its `pkgsModule`, the module that wires `_module.args.pkgs` and
# `_module.check` into every home-manager evaluation.
#
# The real file lists home-manager's whole module tree when `minimal`
# is false and the necessary modules alone when it is true. This one
# lists the options a test configuration sets, plus one module that
# stands for the tree the real file drops: it declares the option a
# minimal configuration has to import for itself.
{
  pkgs,
  lib,
  check ? true,
  useNixpkgsModule ? true,
  minimal ? false,
}:
let
  pkgsModule =
    { ... }:
    {
      config = {
        _module.args.pkgs = lib.mkDefault pkgs;
        _module.check = check;
      };
    };

  optionsModule =
    { ... }:
    {
      options = {
        # What the evaluation reads out of the configuration.
        home.activationPackage = lib.mkOption {
          type = lib.types.str;
          default = "activation-package";
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        news.display = lib.mkOption {
          type = lib.types.str;
          default = "silent";
        };
        news.entries = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };
        programs.home-manager.path = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        # The arguments the evaluation composed, recorded so a test
        # can read them.
        stub = {
          modulesPath = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          minimal = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          useNixpkgsModule = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          # Which module list the evaluation imported, read by name so
          # a test sees the difference the two entry points make.
          moduleList = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
      };
      config.stub = {
        inherit minimal useNixpkgsModule;
        moduleList = if minimal then "necessary" else "whole-tree";
      };
    };

  modulesPathModule =
    { modulesPath, ... }:
    {
      config.stub.modulesPath = modulesPath;
    };

  # A stand-in for the module tree the real file imports when
  # `minimal` is false: an option a configuration can set only if the
  # evaluation brought the tree along. `${modulesPath}/programs.nix`
  # is the file a minimal configuration imports for itself.
  programsModule = import ./programs.nix;
in
[
  pkgsModule
  optionsModule
  modulesPathModule
]
++ lib.optional (!minimal) programsModule
