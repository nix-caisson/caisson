# SPDX-License-Identifier: MIT
#
# A stand-in for `modules/modules.nix` of the home-manager source: the
# module list the evaluation imports, with that file's signature
# (`{ pkgs, lib, check ? true, useNixpkgsModule ? true, minimal ? false }`)
# and its `pkgsModule`, the module that wires `_module.args.pkgs`,
# `_module.check` and `lib = lib.hm` into every home-manager
# evaluation.
#
# The real file lists home-manager's module tree beside that module.
# This one lists the options a test configuration sets and the
# `home.activationPackage`, `news` and `assertions` names the
# evaluation reads, so the arguments the evaluation composes are
# exercised without a nixpkgs.
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
        # The real file sets this to `lib.hm`: inside a home-manager
        # module, `lib` the option is the home-manager library.
        lib = lib.hm;
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
        # The `lib` option of a home-manager module.
        lib = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        # What a test configuration records about the library the
        # module system handed it.
        seenLib = lib.mkOption {
          type = lib.types.attrs;
          default = { };
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
        };
      };
      config.stub = {
        inherit minimal useNixpkgsModule;
      };
    };

  modulesPathModule =
    { modulesPath, ... }:
    {
      config.stub.modulesPath = modulesPath;
    };
in
[
  pkgsModule
  optionsModule
  modulesPathModule
]
