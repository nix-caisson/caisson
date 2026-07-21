# Library Lifecycle

## Overview

caisson builds a composed `lib` by layering overlays on top of `nixpkgs-lib`. This process happens during `mkLib` and determines what functions are available to every module in the flake. Understanding this lifecycle is essential for writing overlays that compose correctly.

## Phases

### 1. Bootstrap

`mkLib` starts by extending the base library (`nixpkgs-lib` by default;
overridable via the `baseLib` argument) with the framework's core
overlay, closed over the caller's `inputs`. This bootstrap library
exists only to mint the input-closed helpers — most importantly the
`mkLibOverlay` passed to the `libOverlays` function. The final `lib` is
**not** built on top of it; composition restarts from the base library
in phase 4.

### 2. Registration

The `libOverlays` argument to `mkLib` is a function that receives the
input-closed `mkLibOverlay` helper and returns the set of registered
overlays (`_mkLibOverlay: { ... }` when everything registered is
already built).

Everything passed through `mkLibOverlay` takes the closure attrset as
its first arg list — `{ closure-inputs, mkLibOverlay, ... }:` — and
returns an `{ imports ? [ ], overlay }` attrset: the `final: prev:`
function under `overlay`, and the overlays it depends on under
`imports` (see
[Library Overlays](./library-overlays.md)). Already-built
overlays (for example another flake's exported `libOverlays.default`)
are registered directly, never wrapped in `mkLibOverlay`:

```nix
libOverlays = mkLibOverlay: {
  default = mkLibOverlay ./lib-overlays/default;
  other = inputs.other-flake.libOverlays.default;
};
```

### 3. Selection

Registration defines the set of available overlays; `libOverlayImports`
selects which of them actually apply to this flake's `lib`:

```nix
libOverlayImports = overlays: builtins.attrValues { inherit (overlays) default; };
```

The default selects every registered overlay. The split matters because
registration also feeds export: a flake can register overlays for
downstream consumers that it does not apply to itself.

### 4. Composition

Starting again from the base library, the framework applies the core
overlay and then the selected overlays, left to right:

```
baseLib  →  extend(core)  →  extend(selected overlays...)  →  final lib
```

Each overlay receives `final` (the fully composed lib) and `prev` (the lib before this overlay). This is the standard Nix overlay contract.

If an overlay needs functions defined by another overlay, it can use the structured format `{ overlay = ...; imports = [...]; }` instead of a bare function. `mkExtendedLib` recursively applies the `imports` before the overlay itself, ensuring dependencies are available in `prev` regardless of the order overlays were registered. See [Library Overlays](./library-overlays.md) for details and examples.

### 5. Distribution

The composed `lib` is threaded into the flake via `mkFlake`:
- Passed as `specialArgs.lib` to flake-parts, so every module receives it
- Available in `perSystem` modules via the standard `lib` argument
- Exported as `flake.lib` when `caisson.lib.export.enabled` is set
  (which requires `caisson.configInfo.configName`; the `name` argument
  to `mkFlake` provides its default)

#### What `flake.lib` contains

`flake.lib` exports **only the flake's own namespace** — `lib.${configName}` — not the full composed library. For a flake with `configName = "my-project"`, `flake.lib` is a flat attrset of that project's public functions: `{ mkHelper = ...; myThing = ...; }`.

It surfaces to consumers as `my-project.lib.mkHelper`, not `my-project.lib.my-project.mkHelper`.

This is intentional:

- **Minimal API surface.** The full composed lib includes all of nixpkgs-lib plus every registered overlay. Exporting it would turn every function — including internal overlays and nixpkgs internals — into an implicit public contract, making it much harder to evolve the implementation.
- **Pin hygiene.** The full lib is built against the exporting flake's own nixpkgs-lib pin. A downstream consumer using functions from that lib would couple themselves to a specific pin they may not control. The `follows` convention exists precisely to let consumers manage their own pin; exporting the full lib undermines it.
- **Consumer model.** A downstream flake can build its own composed lib against its own inputs by calling `mkLib`; the bootstrap functions that takes (`mkLib`, `mkFlake`, etc.) are available directly on `flake.lib`.

This convention applies to any flake built on caisson: export your namespace, not your full lib.

## Overlay Conventions

- **Namespace your additions.** Use a dedicated attribute (e.g., `lib.myProject`) to avoid collisions with nixpkgs-lib.
- **Use `prev` for extension.** Always merge with `prev.myNamespace or {}` to allow upstream overlays to contribute to the same namespace.
- **Keep overlays pure.** Overlays should not depend on `pkgs` or system-specific values -- they operate on `lib`, which is system-independent.

## Example

```nix
# lib-overlays/default/default.nix
{ closure-inputs, ... }:
{
  imports = [ ];
  overlay = final: prev: {
    myProject = (prev.myProject or {}) // {
      helper = x: x + 1;
      upstreamHelper = closure-inputs.some-flake.lib.helper;
    };
  };
}
```

The closure arg list always comes first — `closure-inputs` is the
defining flake's inputs (see [Closed Inputs](./closed-inputs.md)); an
overlay that needs nothing from the closure still takes the arg list,
as `{ ... }:`.

After `mkLib`, `lib.myProject.helper 41` evaluates to `42`.

## Exploring the Composed Library

You can inspect and call functions from the composed `lib` interactively:

```bash
nix repl .
# :p lib                              -- top-level framework functions
# :p lib.myProject                    -- your namespaced additions
# :p lib.myProject.helper 41          -- call a function
```

Or non-interactively:

```bash
nix eval .#lib --apply builtins.attrNames
nix eval .#lib --apply 'lib: lib.myProject.helper 41'
```

## Further Reading

- [Library Overlays](./library-overlays.md) -- why overlays are safe with proper namespacing, input closure, and dependency tracking
- [Closed Inputs](./closed-inputs.md) -- how inputs are closed over in overlays and modules
- `examples/literate-flake/` -- working example with a custom library overlay
