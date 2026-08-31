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
closure = { closure-inputs     : attrs
          ; mkLibOverlay       : freeformOverlay -> libOverlay
          ; mkModule           : string -> freeformModule -> module
          ; contributeModules  : attrs -> attrsOf (attrsOf module) -> attrs
          }
```

Applies the closure attrset to an overlay given as a function or a path to one, and normalizes the result: the built `libOverlay` always carries both keys, with `imports` defaulted to `[ ]`. Already-built overlays are registered directly, never wrapped.

The closure's `mkModule` is bound to the defining composition, so
modules contributed by an overlay close over the definer's inputs and
library. `contributeModules prev { <class>.<name> = module; }`
returns the `caisson.modules` registry merge for the overlay's output
(merge its result with any namespace contributions); it arrives
through the closure rather than the composed library because an
overlay's output attribute names must not depend on `final`. See
[Module classes](../concepts/module-classes.md) for the two
registration channels.

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

## Integration namespaces

Each integration is a library overlay exported by this flake
(`libOverlays.<target>`) and available as a calculus entry via
`lib.composition.entriesFor`. Composing one contributes its
`lib.caisson.<target>` namespace, documented below. Every entry point takes its target
ecosystem as an explicit `ecosystemSrc` argument; the integrations
pin nothing themselves. Common conventions:

- `pkgSets`: an attrset of package sets; `pkgSets.pkgs` is required
  where present and becomes the evaluation's package set (also passed
  through in `specialArgs`/`extraSpecialArgs`).
- `moduleImports`: a selection function over the corresponding class
  registry (`lib.caisson.modules.<class>`), defaulting to all
  registered modules.
- Framework-provided special arguments compose first; the caller's
  win on conflict.

### `caisson.nixos` (module class `nixos`)

- **Source:** `lib-overlays/nixos/default.nix`
- `mkNixosModule : freeformModule -> module`: class-bound `mkModule`.
- `mkSystem : { ecosystemSrc, pkgSets, configModule, moduleImports?,
  specialArgs?, ... } -> nixosSystem`: evaluates
  `<ecosystemSrc>/nixos/lib/eval-config.nix` (a nixpkgs source tree)
  with the selected class modules, the config module, and a framework
  module pinning `nixpkgs.pkgs` to `pkgSets.pkgs`. Extra arguments
  pass through to `eval-config.nix`.
- `mkSystemFull`: as `mkSystem`, additionally passing nixpkgs'
  `module-list.nix` as `baseModules`.
- `mkSystemMinimal : { ecosystemSrc, prefix?, ... }`: bare
  `evalModules` from `<ecosystemSrc>/nixos/lib`; no NixOS base
  modules, so the config module declares any options it uses.

### `caisson.home-manager` (module class `homeManager`)

- **Source:** `lib-overlays/home-manager/default.nix`
- `mkHomeManagerModule : freeformModule -> module`.
- `mkHomeConfiguration : { ecosystemSrc, pkgSets, configModule,
  moduleImports?, extraSpecialArgs?, osConfig?, check?, minimal?,
  sourceMeta? } -> homeConfiguration`: runs home-manager's own
  evaluator (`<ecosystemSrc>/modules`). Source metadata defaults
  derive from what actually composes: `homeManagerOutPath` from
  `ecosystemSrc` and `nixpkgsOutPath` from `pkgSets.pkgs.path`
  (`schemaVersion` 3).
- `mkHomeConfigurationMinimal`: `mkHomeConfiguration` with
  `minimal = true`.
- `mkStandaloneAdapter : { moduleImports?, ... } -> { homeModules,
  buildHome }`: the selected class modules plus a `buildHome`
  closure over the same arguments.
- `mkNixosAdapter : { users, ecosystemSrc, hostName?, hostKind?,
  baseSystem?, sourceMeta?, moduleImports?, sharedModules?,
  useGlobalPkgs?, useUserPackages?, activationMode?,
  extraSpecialArgs?, ... } -> module (nixos class)`: embeds
  home-manager in a NixOS generation. `activationMode = "upstream"`
  uses home-manager's own NixOS module; `"user-service"` embeds
  standalone activation packages behind a `ConditionUser` user unit
  and never touches `users.users` (safe for systemd-homed hosts; one
  hosted user). Both write `/etc/caisson-home-manager/source.json`
  for the drift check.
- `mkSourceMeta`, `assertSourceCoherence`: source-provenance records
  and the fingerprint comparison used by the drift machinery.

### `caisson.nixpkgs`

- **Source:** `lib-overlays/nixpkgs/default.nix`
- `mkScope : pkgs -> (callPackage -> attrs) -> scope`: a
  `makeScope` wrapper handing the scope function its `callPackage`.
- `mkPackagesOverlay : pkgsFn -> name -> overlayFn`: turns a scope
  function (or path; optionally context-taking
  `{ callPackage, inputs, lib }`) into an overlay that merges the
  scope under attribute `name`.
- `mkPolyfillOverlay : overlayFn -> name -> overlayFn`: wraps an
  overlay (or path; optionally context-taking) for registration
  alongside package overlays; the name is ignored.
- `types.nixpkgsOverlay`, `types.nixpkgs`: option types.

### `caisson.colmena` (module class `colmena`)

- **Source:** `lib-overlays/colmena/default.nix`
- `mkColmenaModule : freeformModule -> module`.
- `mkColmenaHive : { ecosystemSrc, modules?, moduleImports?,
  specialArgs?, ... } -> hive`: `ecosystemSrc.lib.makeHive` over the
  passthrough arguments, with the selected class modules and
  framework `specialArgs` merged into `meta` and `defaults`.

### `caisson.terranix` (module class `terranix`)

- **Source:** `lib-overlays/terranix/default.nix`
- `mkTerranixModule : freeformModule -> module`.
- `mkTerranixConfiguration : { ecosystemSrc, modules?, moduleImports?,
  extraArgs?, ... } -> derivation`:
  `ecosystemSrc.lib.terranixConfiguration` with the selected class
  modules and framework `extraArgs`.

### `caisson.system-manager` (module class `systemManager`)

- **Source:** `lib-overlays/system-manager/default.nix`
- `mkSystemManagerModule : freeformModule -> module`.
- `mkSystemConfig : { ecosystemSrc, modules?, moduleImports?,
  specialArgs?, ... } -> systemConfig`:
  `ecosystemSrc.lib.makeSystemConfig` with the selected class
  modules, plus a compatibility bridge for the current
  nixos-unstable restructuring of the NixOS nix module (each half
  self-retires; see the source comments).
