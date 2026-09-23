# SPDX-License-Identifier: MIT
#
# A stand-in for `nixos/lib/eval-config.nix` of a nixpkgs source tree,
# with that file's signature and its treatment of `lib`: the library
# it is given is what `evalModules` runs on, what the `pkgsModule` and
# the module locations are built with, and what the result publishes
# as `lib`. `lib` defaults to `import ../../lib`, the library of the
# tree this file lives in, so an evaluation handed none of its own
# lands in the `lib` directory beside this one.
#
# The real file draws `evalModules` from `./default.nix` of this
# directory with the `minimalModules` feature flag, and this one does
# the same, so the library reaches the module system by the route it
# reaches it upstream.
evalConfigArgs@{
  system ? builtins.currentSystem,
  pkgs ? null,
  baseModules ? import ../modules/module-list.nix,
  specialArgs ? { },
  modules,
  modulesLocation ? (builtins.unsafeGetAttrPos "modules" evalConfigArgs).file or null,
  prefix ? [ ],
  lib ? import ../../lib,
  extraModules ? [ ],
}:
let
  evalModulesMinimal =
    (import ./default.nix {
      inherit lib;
      featureFlags.minimalModules = { };
    }).evalModules;

  pkgsModule = {
    _file = ./eval-config.nix;
    config = lib.mkMerge (
      (lib.optional (system != null) { stub.system = lib.mkDefault system; })
      ++ (lib.optional (pkgs != null) { stub.pkgs = pkgs; })
    );
  };

  # The options this stand-in declares in place of the NixOS module
  # tree, so a configuration module has somewhere to record what it
  # saw. The real base modules arrive through `baseModules`, which
  # `mkConfigurationFull` fills from the tree's module list.
  optionsModule =
    { ... }:
    {
      options = {
        stub = {
          system = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          pkgs = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          modulesPath = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          baseModules = lib.mkOption {
            type = lib.types.int;
            default = 0;
          };
        };
      };
      config.stub.baseModules = builtins.length baseModules;
    };

  modulesPathModule =
    { modulesPath, ... }:
    {
      config.stub.modulesPath = modulesPath;
    };

  userModules =
    if modulesLocation == null then
      modules
    else
      map (lib.setDefaultModuleLocation modulesLocation) modules;

  evaluated = evalModulesMinimal {
    inherit prefix specialArgs;
    modules =
      baseModules
      ++ extraModules
      ++ [
        pkgsModule
        optionsModule
        modulesPathModule
      ]
      ++ userModules;
  };
in
evaluated
// {
  inherit lib;
  libArgument = lib;
}
