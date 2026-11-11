# SPDX-License-Identifier: MIT
#
# A NixOS module that the flake `publisher` of the pinned-world suite
# registers and publishes in its `modules` output. The check
# `aPublishedModuleEvaluatesUnderPlainNixosSystem` evaluates it with
# `nixosSystem` of nixpkgs, which gives it the library of nixpkgs as
# `lib`.
#
# The module writes a file into `/etc`. The file holds the name of the
# composition that defined the module, read from `closure-lib`, and
# whether the `lib` of the evaluation has `caisson`.
{ closure-lib, ... }:
{ lib, ... }:
{
  environment.etc."pinned-world/published.json".text = builtins.toJSON {
    definedIn = closure-lib.caisson-core.libManifest.name;
    evaluatorLibHasCaisson = lib ? caisson;
  };
}
