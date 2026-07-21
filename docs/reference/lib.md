# Library Reference

This reference documents the `lib.caisson` API exported by the core library overlay.

Type notation used below:

- `lib` — a composed nixpkgs-style library attrset
- `module` — a module for some module class's module system
- `overlayFn` — `final: prev: attrs`, the standard overlay function
- `libOverlay` — `{ imports : listOf libOverlay; overlay : overlayFn }`,
  the built overlay produced by `mkLibOverlay` (both keys always present)
- `path` arguments are imported before the rules below apply

## Functions

### `mkLib`

- **Source:** `lib-overlays/core/default.nix`

```
mkLib :
  { inputs            : attrs                              # the defining flake's inputs
  , baseLib           ? inputs.nixpkgs-lib.lib : lib
  , modules           ? (lib: { })
                      : lib -> attrsOf (attrsOf module)    # class -> name -> module
  , libOverlays       ? (mkLibOverlay: { })
                      : (freeformOverlay -> libOverlay) -> attrsOf libOverlay
  , libOverlayImports ? builtins.attrValues
                      : attrsOf libOverlay -> listOf libOverlay
  } -> lib
```

Builds a composed library by extending `baseLib` with the core overlay and the selected local overlays. This is the primary entry point for creating the final `lib` used by `mkFlake`.

- `modules` receives the composed `lib` (usable through the fixpoint) and returns the class-keyed registration, typically built with helpers like `lib.caisson.mkFlakeModule`.
- `libOverlays` receives the input-closed `mkLibOverlay` helper and returns the registered overlays. Both arguments take exactly the function shape shown; passing anything else is an error.
- `libOverlayImports` selects which registered overlays apply to this flake's own `lib`; registration also feeds export, so the two can differ.

### `mkFlake`

- **Source:** `lib-overlays/core/default.nix`

```
mkFlake :
  { configModule  : module                                  # flake class
  , moduleImports ? (modules: modules)
                  : attrsOf module -> attrsOf module        # selection from modules.flake
  , name          ? null : nullOr string                    # rev-independent module identity
  , ...                                                     # forwarded to flake-parts mkFlake
  } -> flakeOutputs
```

Builds final flake outputs via `flake-parts` using the composed `lib` and module graph assembled by `mkLib`. `name` sets flake-parts' `moduleLocation` (so exported modules deduplicate across revs) and defaults `caisson.configInfo.configName`.

### `mkModule`

- **Source:** `lib-overlays/core/default.nix`

```
mkModule : string -> freeformModule -> module

freeformModule = path | (closure -> module)
closure = { closure-inputs        : attrs    # the defining flake's inputs
          ; closure-lib           : lib      # the defining flake's composed lib
          ; closure-self-modules  : attrs    # the defining flake's registrations
                                             #   in the same class
          ; mkModule              : freeformModule -> module   # bound to the class
          }
```

Factory for class-specific module normalizers. Given a class name, returns a normalizer that applies the closure attrset to a module given as a function or a path to one; the module takes the closure as its first arg list (`{ ... }:` when unused). Plain modules are imported/registered directly, never wrapped. Path modules gain `_file` and a path-based dedup `key`.

The `mkModule` closure member is bound to the same class, so nested module composition stays in that class.

### `mkFlakeModule`

- **Source:** `lib-overlays/core/default.nix`

```
mkFlakeModule : freeformModule -> module    # = mkModule "flake"
```

Convenience form of `mkModule "flake"` for flake-parts modules.

### `mkLibOverlay`

- **Source:** `lib-overlays/core/default.nix`

```
mkLibOverlay : freeformOverlay -> libOverlay

freeformOverlay = path | (closure -> { imports ? listOf libOverlay
                                     ; overlay : overlayFn })
closure = { closure-inputs : attrs
          ; mkLibOverlay   : freeformOverlay -> libOverlay
          }
```

Applies the closure attrset to an overlay given as a function or a path to one, and normalizes the result: the built `libOverlay` always carries both keys, with `imports` defaulted to `[ ]`. Already-built overlays are registered directly, never wrapped.

### `importApply`

- **Source:** `lib-overlays/core/default.nix`

```
importApply : freeformModule -> attrs -> module
```

Applies static arguments to a module through `_file`/`imports` wrappers while preserving wrapper metadata. Used for threading arguments through module import chains.

### `callConsumerFlake`

- **Source:** `lib-overlays/core/default.nix`

```
callConsumerFlake :
  { path       : path | string   # directory containing flake.nix
  , pool       ? { } : attrs     # inputs resolvable by name
  , overrides  ? { } : attrs     # highest-precedence injections
  , sourceInfo ? { } : attrs     # extra self attrs (lastModified, rev, ...)
  } -> flakeOutputs              # self: inputs, outputs, outPath, _type
```

Evaluates a consumer-style flake from source with explicitly supplied
inputs — the heart of integration testing. The flake's declared inputs
resolve by name: `overrides` first, then `follows` chains through the
other resolved inputs, then `pool`; an unresolvable input throws an
error naming it. The self fixpoint and decoration are handled by the
shared `call-flake` kernel (also used by the eval-weight harness).
Nothing is fetched: locks are not read, and `sourceInfo` attrs appear
only if supplied. See [Testing](../testing.md).

### `eval-weight`

- **Source:** `lib-overlays/core/eval-weight/`

The evaluation-cost measurement harness: `eval-weight.mkCheck` builds a
check derivation that measures eval scenarios in a sandbox and gates
deterministic metrics against a committed baseline. Documented in
[Evaluation weight](../eval-weight.md).

## Types

### `types.libOverlay`

- **Source:** `lib-overlays/core/default.nix`

A module-system option type for built library overlays. Its `check`
verifies the structure recursively: an attrset with an `overlay`
function and a (possibly absent) `imports` list whose entries are
themselves valid `libOverlay`s. Used by options that carry overlays,
such as `caisson.libOverlays.exported`.
