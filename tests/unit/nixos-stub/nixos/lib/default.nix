# SPDX-License-Identifier: MIT
#
# A stand-in for `nixos/lib/default.nix` of a nixpkgs source tree,
# with that file's signature and its treatment of `lib`: the library
# it is given is what `evalModules` runs on, and `lib` defaults to
# `import ../../lib`, the library of the tree this file lives in. The
# nixos-minimal integration imports this file directly, so the library
# it names here is the one that reaches a minimal evaluation.
{
  lib ? import ../../lib,
  featureFlags ? { },
  ...
}:
{
  evalModules =
    {
      prefix ? [ ],
      modules ? [ ],
      specialArgs ? { },
    }:
    lib.evalModules {
      inherit prefix modules;
      class = "nixos";
      specialArgs = {
        modulesPath = toString ../modules;
      }
      // specialArgs;
    }
    // {
      libArgument = lib;
      stubFeatureFlags = featureFlags;
    };
}
