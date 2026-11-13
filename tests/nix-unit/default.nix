# SPDX-License-Identifier: MIT
#
# The nix-unit integration over a flake-parts caisson top evaluated for
# x86_64-linux and aarch64-linux (configs/flake/nix-unit). `inputs` is
# the dependency pool of the checks configuration of caisson, with
# `caisson` set to the flake of caisson.
#
# The caisson top declares the nix-unit configurations `passing` and
# `failing`. The check record holds the check `unit` of each, of the
# category `unit`, for both systems, under `passing/unit` and
# `failing/unit`, since the checks share their name. The check of
# `passing` builds for
# x86_64-linux: nix-unit runs its cases in the build sandbox over the
# library composed again there. The check of `failing` fails to build,
# and its log reports the failing case as failed and the passing case
# as passed.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = inputs.nixpkgs.legacyPackages.${system};

  lib = core.mkLib {
    name = "nix-unit";
    dependencies = {
      inherit (inputs) nixpkgs flake-parts;
    };
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = dependencies: {
      nixpkgs-lib = dependencies.nixpkgs;
    };
    configs = lib: lib.caisson-core.mkModules ./configs;
    pkgSets = lib: {
      default = lib.caisson.nixpkgs.mkConfiguration { };
    };
  };

  top = lib.caisson.flake-parts.mkTopConfiguration { };

  record = top.caisson.manifest.checkRecord;

  categories = builtins.mapAttrs (
    _: entries:
    builtins.mapAttrs (_: entry: entry.category) (builtins.removeAttrs entries [ "registries" ])
  ) record;

  expectedCategories = {
    "failing/unit" = "unit";
    "passing/unit" = "unit";
  };

  failing = pkgs.testers.testBuildFailure top.checks.${system}."failing/unit";
in
assert
  categories == {
    x86_64-linux = expectedCategories;
    aarch64-linux = expectedCategories;
  }
  || throw "the check record of the nix-unit test holds the categories ${builtins.toJSON categories}";
pkgs.runCommand "nix-unit-integration"
  {
    passing = top.checks.${system}."passing/unit";
    inherit failing;
  }
  ''
    grep -qF '❌ testFailsOnPurpose' $failing/testBuildFailure.log
    grep -qF '✅ testPasses' $failing/testBuildFailure.log
    touch $out
  ''
