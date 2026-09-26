# SPDX-License-Identifier: MIT
#
# A stand-in for `modules/default.nix` of the home-manager source: the
# standalone evaluator, with that file's signature
# (`{ configuration, pkgs, lib ? pkgs.lib, minimal ? false, check ? true,
# extraSpecialArgs ? { } }`) and the steps the integration composes
# for. It forwards `minimal` to the module list, evaluates the class
# and publishes the names the real file adds beside the configuration.
{
  configuration,
  pkgs,
  lib ? pkgs.lib,
  minimal ? false,
  check ? true,
  extraSpecialArgs ? { },
}:
let
  hmModules = import ./modules.nix {
    inherit
      check
      pkgs
      minimal
      lib
      ;
  };

  rawModule = lib.evalModules {
    modules = [ configuration ] ++ hmModules;
    class = "homeManager";
    specialArgs = {
      modulesPath = toString ./.;
    }
    // extraSpecialArgs;
  };
in
rawModule
// {
  inherit (rawModule.config.home) activationPackage;
  newsDisplay = rawModule.config.news.display;
  newsEntries = rawModule.config.news.entries;
}
