# SPDX-License-Identifier: MIT
#
# The expression nix-unit evaluates inside the build sandbox of the
# check `unit` of a nix-unit configuration. Nix runs the builder of a
# derivation in a sandbox without network access, so nothing in this
# file may fetch: no pin reader runs here, and every source is a store
# path that the derivation names as a dependency.
#
# `data` is the JSON file the nix-unit integration writes
# (lib-overlays/nix-unit/default.nix), which holds:
#
# - `callFlake`, the store path of caisson's call-flake.nix, and
#   `core`, the store path of the caisson-core source that composed
#   the library;
# - `nodes`, every pinned source the library and the configuration
#   reach, by an identifier: its store path, whether it is a flake, the
#   identifiers of its inputs, and its source information (`rev`,
#   `narHash` and the like);
# - `composition`, what the mkLib call that composed the library
#   declared, with each registry entry named by the file it was
#   registered from;
# - `dependencies`, the dependencies of the nix-unit configuration, and
#   `tests`, the file nix-unit reads.
#
# A source that is a flake is evaluated again here with `callFlake`,
# over its inputs, so a registration that reads the outputs of a flake
# reads the same outputs here. The library is composed again with
# mkLib of that caisson-core from the same declaration, and the file of
# the tests is called with it.
{ data }:
let
  spec = builtins.fromJSON (builtins.readFile data);

  callFlake = import spec.callFlake;

  # Each source, as Nix hands a flake its inputs: a flake as its
  # outputs with its source information, `inputs`, `outPath` and
  # `sourceInfo`, and a source that is no flake as its source
  # information and `outPath`.
  nodes = builtins.mapAttrs (
    _: node:
    let
      sourceInfo = node.info // {
        outPath = node.path;
      };
    in
    if node.flake then
      callFlake {
        src = node.path;
        inputs = builtins.mapAttrs (_: id: nodes.${id}) node.inputs;
        sourceInfo = node.info // {
          inherit sourceInfo;
        };
      }
    else
      sourceInfo
  ) spec.nodes;

  sourcesOf = builtins.mapAttrs (_: id: nodes.${id});

  inherit (spec) composition;

  core = import spec.core;

  given = name: value: if value == null then { } else { ${name} = value; };

  lib = core.mkLib (
    {
      dependencies = sourcesOf composition.dependencies;
      root =
        if composition.root == null then
          null
        else
          composition.root.info // { outPath = composition.root.path; };
      # The registry entries, each made from the file it was registered
      # from by the constructor of the library, as the directory readers
      # of caisson-core make them (`mkModules`, `mkLibOverlays`,
      # `mkPkgOverlays`).
      libOverlays = lib: builtins.mapAttrs (_: lib.caisson-core.mkLibOverlay) composition.libOverlays;
      modules =
        lib:
        builtins.mapAttrs (
          class: builtins.mapAttrs (_: lib.caisson-core.mkModule class)
        ) composition.modules;
      configs =
        lib:
        builtins.mapAttrs (
          class: builtins.mapAttrs (_: lib.caisson-core.mkModule class)
        ) composition.configs;
      pkgOverlays = lib: builtins.mapAttrs (_: lib.caisson-core.mkPkgOverlay) composition.pkgOverlays;
      # The lib overlays the library applied, by registry name, in the
      # order it applied them.
      libOverlayImports =
        lib:
        builtins.map (name: lib.caisson-core.libManifest.libOverlays.${name}) composition.libOverlayImports;
    }
    // given "name" composition.name
    // given "systems" composition.systems
    // (
      if composition.projects == { } then
        { }
      else
        {
          projects = sourcesOf composition.projects;
        }
    )
    // (
      if composition.defaultEcosystemSrc == { } then
        { }
      else
        {
          defaultEcosystemSrc =
            dependencies: builtins.mapAttrs (_: name: dependencies.${name}) composition.defaultEcosystemSrc;
        }
    )
    // (
      if composition.pkgSets == [ ] then
        { }
      else
        {
          # The package configs keep their names. Their declarations
          # are functions, which the record does not hold, so a test
          # that reads a package config fails with this message.
          pkgSets =
            _lib:
            builtins.listToAttrs (
              builtins.map (name: {
                inherit name;
                value = throw ''
                  caisson: a nix-unit test read the package config `${name}` of the library.
                  nix-unit runs the tests in the build sandbox over the library composed again
                  from its record, and the record holds no declaration of a package config.
                '';
              }) composition.pkgSets
            );
        }
    )
  );

  suite = import spec.tests;
in
suite {
  inherit lib;
  manifest = lib.caisson-core.libManifest;
  dependencies = sourcesOf spec.dependencies;
}
