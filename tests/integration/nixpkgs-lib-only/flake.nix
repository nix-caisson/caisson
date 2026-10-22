# SPDX-License-Identifier: MIT
{
  description = "Integration test: a package set built on a library source that holds only nixpkgs' lib directory";

  inputs = {
    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      core = parent.lib.caisson;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) sources root;
        name = "nixpkgs-lib-only";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
        };
        # The library comes from a copy of the `lib` directory alone,
        # laid out as the nixpkgs.lib mirror is. The package set comes
        # from the full checkout, pinned as `nixpkgs`.
        defaultEcosystemSrc = sources: {
          nixpkgs-lib = builtins.path {
            path = "${sources.nixpkgs}/lib";
            name = "nixpkgs-lib-only";
          };
        };
        libOverlays = lib: lib.caisson.mkLibOverlays ./lib-overlays;
        pkgSets = lib: { default = lib.caisson.nixpkgs.mkConfiguration { }; };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/nixpkgs-lib-only;
    };
}
