# SPDX-License-Identifier: MIT
#
# A stand-in for home-manager's standalone evaluator, with its
# signature and its treatment of `lib`: the library it is given,
# extended with an `hm` namespace, is what the module system runs on
# (home-manager does this in modules/lib/stdlib-extended.nix). The
# result reports what the evaluation saw, so a test can read the
# library the module system used.
{
  configuration,
  pkgs,
  lib ? pkgs.lib,
  minimal ? false,
  check ? true,
  extraSpecialArgs ? { },
}:
let
  extendedLib = lib.extend (
    _self: _super: {
      hm.marker = "from-the-evaluator";
    }
  );
  evaluated = extendedLib.evalModules {
    modules = [
      configuration
      {
        options.seenLib = extendedLib.mkOption { type = extendedLib.types.attrs; };
        config._module.check = check;
      }
    ];
    class = "homeManager";
    specialArgs = extraSpecialArgs;
  };
in
{
  inherit
    check
    minimal
    pkgs
    ;
  libArgument = lib;
  inherit (evaluated) config;
}
