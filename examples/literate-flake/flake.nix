# SPDX-License-Identifier: MIT
{
  description = "Literate example flake demonstrating caisson framework usage";

  inputs = {
    /*
      This example lives inside the caisson repository, so its inputs use two
      patterns that differ from what an independent downstream flake would do:

      **Floating reference (`path:`):**  `caisson` points at the repository
      root via a relative path.  Nix resolves this against the local source
      tree, so standalone evaluation (`nix flake check` in this directory)
      always tests the current working copy -- no push/lock cycle required.
      The checks partition achieves the same effect by passing `caisson = self;`
      when it fabricates inputs.

      **Shared dependency pinning (`deps` / `follows`):**  Common dependencies
      (nixpkgs, flake-parts) are declared in `tests/dependencies/flake.nix`
      and inherited here via `follows`.  This keeps every test and example flake
      on the same versions without maintaining separate lockfiles.

      A standalone consumer flake would instead declare all inputs directly:

          caisson.url = "github:nix-caisson/caisson";
          nixpkgs.url  = "github:NixOS/nixpkgs/nixos-unstable";
          flake-parts.url = "github:hercules-ci/flake-parts";
    */
    deps.url = "path:../../tests/dependencies";

    caisson.url = "path:../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      caisson,
      ...
    }:
    let
      /*
        Step 1: Bootstrap a composed library.

        `caisson-core.mkLib` composes a library from registered overlays and
        injects the machinery, the module registry, and the manifest under
        `lib.caisson-core`. Your own overlays contribute your extensions
        (here, `lib.literate-flake`).

        - `inputs` are closed over so that modules and overlays can reference
          them without threading inputs explicitly through every call site.
        - `projects` registers whole upstream contributions: a consumed
          project's exported overlays and modules become available under
          `<project>/<name>`, and the usual selections pick from them per
          item. Registering caisson this way brings in its integrations
          (`lib.caisson`, the flake-parts one included) and its exported modules.
        - `modules` is a function from the composed `lib` returning the
          class-keyed registration. `mkModules` derives it from the
          conventional layout, `modules/<class>/<name>/default.nix`:
          each entry directory becomes `modules.<class>.<name>`, built
          with `caisson-core.mkModule <class>`. Everything passed to
          mkModule takes the closure attrset ({ closure-inputs,
          closure-lib, mkModule, ... }) as its first arg list; files
          that don't need it take `{ ... }:`.
        - `configs` is the same registration for `configs/<class>/<name>`,
          the configurations a top evaluates.
        - `libOverlays` is a function from an input-closed `mkLibOverlay`
          helper returning the registered library overlays; `mkLibOverlays`
          derives it from `lib-overlays/<name>/default.nix`. Registering
          one by hand stays useful for cherry-picking or renaming a single
          overlay from elsewhere.
      */
      core = caisson.lib.caisson-core;

      lib = core.mkLib {
        inherit inputs;

        projects = {
          inherit caisson;
        };

        modules = core.mkModules ./modules;
        configs = core.mkModules ./configs;
        libOverlays = core.mkLibOverlays ./lib-overlays;
      };
    in
    /*
      Step 2: Create the flake outputs.

      `lib.caisson.flake-parts.mkConfiguration` wraps flake-parts' mkFlake, injecting the framework's core
      module and threading `lib` as a special arg so modules receive
      the fully composed library.

      - `configModule` is the flake's top-level configuration (systems,
        caisson settings, per-system packages, etc.), here the registered
        configuration `configs/flake/literate-flake`.
      - `moduleImports` returns the list of registered flake-class modules
        to activate, like `libOverlayImports` for overlays; the consumed
        project's modules select under their prefixed names. When it is
        omitted, every registered entry named `default` applies: this
        flake's own and "caisson/default", caisson's default module (the
        nixpkgs integration's module layer). The `core` entries of the
        class apply to every evaluation regardless.
    */
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson-core.configs.flake.literate-flake;
    };
}
