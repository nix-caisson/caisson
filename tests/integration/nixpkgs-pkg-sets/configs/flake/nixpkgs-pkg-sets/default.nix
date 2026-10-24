# SPDX-License-Identifier: MIT
#
# Reads the package configs mkLib recorded and checks the sets the
# nixpkgs integration built: the same derivations as nixpkgs'
# `import nixpkgs { system; }`, variants included, the registered
# overlay and config module applied where selected, and each set
# carrying its manifest in `pkgs.lib`.
{ ... }:
{
  inputs,
  lib,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { system, ... }:
    let
      configs = lib.caisson.nixpkgs.pkgSets;
      setOf = config: config.children.nixpkgs.${system}.value;
      pkgs = setOf configs.default;
      unfree = setOf configs.unfree;
      upstream = import inputs.nixpkgs { inherit system; };
      same = path: (lib.getAttrFromPath path pkgs).drvPath == (lib.getAttrFromPath path upstream).drvPath;
      pkgsManifest = pkgs.lib.caisson.pkgsManifest;
      # The package config as the legacy readers take it. This
      # evaluation is pure, so the result is the functor alone.
      top = lib.caisson.nixpkgs.mkTopPkgSet configs.default;
      fails = value: !(builtins.tryEval value).success;
      marked = top {
        inherit system;
        overlays = [ (_final: _prev: { topMarker = "ok"; }) ];
      };
      # The traced set of the same package config, and a package made
      # from it by two further steps.
      traced = configs.default.traced.children.nixpkgs.${system}.value;
      bottom = traced.hello.caissonTrace;
      renamed = (traced.hello.override { }).overrideAttrs (_: {
        pname = "hello-traced";
      });
      chain = lib.caisson.nixpkgs.traceChainOf renamed;
    in
    {
      checks.nixpkgs-pkg-sets =
        assert same [ "hello" ];
        assert same [ "curl" ];
        assert same [
          "pkgsStatic"
          "hello"
        ];
        assert same [
          "pkgsCross"
          "aarch64-multiplatform"
          "hello"
        ];
        # A variant that re-enters with a different config.
        assert same [
          "pkgsChecked"
          "hello"
        ];
        assert pkgs ? nixpkgs-pkg-sets && pkgs.nixpkgs-pkg-sets ? sample;
        assert unfree.config.allowUnfree;
        assert !(pkgs.config.allowUnfree or false);
        assert pkgsManifest.name == system;
        assert pkgsManifest.parent.name == "default";
        assert (lib.caisson.manifestOf pkgs).type == "nixpkgs";
        assert configs.default.parent.childless;
        assert !(configs.default.parent ? pkgSets);
        assert configs.default.pkgOverlays == [ "default" ];
        assert (top { inherit system; }).hello.drvPath == pkgs.hello.drvPath;
        assert (top { inherit system; }).lib.caisson.pkgsManifest.name == system;
        assert marked.topMarker == "ok" && marked ? nixpkgs-pkg-sets;
        assert fails (top { system = "riscv64-linux"; }).hello.drvPath;
        assert fails
          (top {
            inherit system;
            config.allowUnfree = true;
          }).hello.drvPath;
        assert fails (top { }).hello.drvPath;
        assert !(top ? hello);
        # A traced package is the same derivation, and carries how it
        # was made. The set that is not traced carries nothing.
        assert traced.hello.drvPath == pkgs.hello.drvPath;
        assert !(pkgs.hello ? caissonTrace);
        assert bottom.step == "callPackage" && bottom.from == null;
        assert lib.hasSuffix "/hello/package.nix" bottom.file;
        assert builtins.elem "stdenv" bottom.resolved;
        assert
          bottom.set == {
            config = "default";
            inherit system;
          };
        assert
          builtins.map (step: step.step) chain == [
            "overrideAttrs"
            "override"
            "callPackage"
          ];
        assert (builtins.elemAt chain 2).drvPath == pkgs.hello.drvPath;
        assert (builtins.elemAt chain 1).from == pkgs.hello.drvPath;
        assert
          renamed.drvPath == ((pkgs.hello.override { }).overrideAttrs (_: {
            pname = "hello-traced";
          })).drvPath;
        assert lib.caisson.nixpkgs.traceChainOf pkgs.hello == null;
        pkgs.runCommand "nixpkgs-pkg-sets" { } "touch $out";
    };
}
