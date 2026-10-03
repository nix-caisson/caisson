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
      pkgsManifest = pkgs.lib.caisson-core.pkgsManifest;
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
        # A variant that re-enters with its own config.
        assert same [
          "pkgsChecked"
          "hello"
        ];
        assert pkgs ? nixpkgs-pkg-sets && pkgs.nixpkgs-pkg-sets ? sample;
        assert unfree.config.allowUnfree;
        assert !(pkgs.config.allowUnfree or false);
        assert pkgsManifest.name == system;
        assert pkgsManifest.parent.name == "default";
        assert (lib.caisson-core.manifestOf pkgs).type == "nixpkgs";
        assert configs.default.parent.childless;
        assert !(configs.default.parent ? pkgSets);
        assert configs.default.pkgOverlays == [ "default" ];
        pkgs.runCommand "nixpkgs-pkg-sets" { } "touch $out";
    };
}
