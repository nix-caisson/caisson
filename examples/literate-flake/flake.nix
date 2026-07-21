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
      (nixpkgs, flake-parts) are declared once in `tests/dependencies/flake.nix`
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

        `mkLib` extends nixpkgs-lib with the framework's core overlay and any
        local overlays you provide. The resulting `lib` has the full `caisson`
        namespace plus your own extensions (here, `lib.literate`).

        - `inputs` are closed over so that modules and overlays can reference
          them without threading inputs explicitly through every call site.
        - `modules` is a function from the composed `lib`, used to register
          class-keyed modules.
        - `libOverlays` is a function from an input-closed `mkLibOverlay`
          helper, used to register library overlays without a separate bootstrap
          library in downstream flakes.
      */
      lib = caisson.lib.mkLib {
        inherit inputs;

        modules = lib: {
          # Demonstrate class-keyed module registration.
          # This class is not imported by mkFlake in this example.
          generic = {
            noop = lib.caisson.mkModule "generic" ({ ... }: { });
          };
          flake = {
            # Import the framework's default module, which provides configInfo,
            # lib export, flakeModules export, and libOverlays export options.
            caisson-default = inputs.caisson.flakeModules.default;

            # Register this flake's own module. Everything passed to mkModule
            # takes the closure attrset ({ closure-inputs, closure-lib,
            # mkModule, ... }) as its first arg list; files that don't need it
            # take `{ ... }:`.
            default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
          };
        };

        libOverlays = mkLibOverlay: {
          # Register a local library overlay. After mkLib completes, its
          # attributes are available on the composed `lib` (e.g. lib.literate).
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    /*
      Step 2: Create the flake outputs.

      `mkFlake` wraps flake-parts' mkFlake, injecting the framework's core
      module and threading `lib` as a special arg so every module receives
      the fully composed library.

      - `configModule` is the flake's top-level configuration (systems,
        caisson settings, per-system packages, etc.).
      - `moduleImports` selects which of the registered flakeModules to
        activate. This is how you control which modules participate in
        evaluation.
    */
    lib.caisson.mkFlake {
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/literate-flake;

      moduleImports = modules: {
        inherit (modules) caisson-default default;
      };
    };
}
