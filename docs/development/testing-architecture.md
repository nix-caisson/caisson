# Testing Architecture

This document explains how caisson's tests are wired into the flake's check
infrastructure. The setup is non-obvious: test flakes live as independent
`flake.nix` files in the source tree but are not evaluated by the Nix flake
machinery. Instead, a flake-parts partition evaluates each one from source with
`lib.caisson-core.callConsumerFlake`, which wires inputs explicitly.

> **Nix version note (2.31.3, March 2026):** The evaluate-from-source pattern
> exists because the Nix flake machinery cannot natively evaluate nested flakes
> within a parent flake's evaluation, and `builtins.getFlake` cannot handle paths
> in pure mode. If future Nix versions add first-class support for nested flake
> evaluation or lift the pure-mode path restriction, this wiring could be
> replaced with direct flake calls.

For commands and test conventions, see [testing.md](./testing.md).

## Overview

All checks are produced by the **checks partition**
(`configs/flake-parts/caisson/partitions/checks.nix`). This partition:

1. Pulls in development-time dependencies from `tests/dependencies` via
   `lib.caisson-core.partitionExtraInputs`
2. Evaluates each test and example flake from source with
   `callConsumerFlake`, resolving the flake's declared inputs from a shared
   pool
3. Merges the resulting `checks.<system>` attrsets, plus a few inline checks
   and the eval-weight gate, into caisson's top-level `checks` output

The partition mechanism (`partitionedAttrs.checks = "checks"`) causes flake-parts
to replace the main evaluation's `checks` with the partition's `checks`, so
`nix flake check` runs everything the partition defines.

## The Checks Partition

### The reason for the partition

flake-parts partitions allow a flake to declare outputs that depend on inputs not
listed in the main `flake.nix`. caisson declares no flake inputs (its own
composition trees are hidden pins in `pins.nix`), and it deliberately avoids
depending on full `nixpkgs` or development tools like `nix-unit`. The checks
partition brings in these heavier dependencies without polluting the main
flake's input set or forcing consumers to fetch them.

### How the extra inputs load

The partition declares:

```nix
extraInputs = lib.caisson-core.partitionExtraInputs ../../../../tests/dependencies;
```

`partitionExtraInputs` (part of caisson-core's kernel) loads the lockfile'd
dependencies flake and returns its resolved inputs. It goes through the
kernel's patched `flake-compat` rather than `builtins.getFlake`, which cannot
handle paths in pure evaluation mode, and it stays safe under read-only
evaluation (`nix flake check --no-build`). The returned inputs are merged into
the partition's `inputs` module argument; this is how `nixpkgs`, `nix-unit`,
`treefmt-nix`, and the rest become available inside the partition module
without being declared in the main `flake.nix`.

### Partition module structure

Inside the partition module, `inputs` contains both the main flake's inputs and the
extra inputs from the dependencies flake. `self` refers to caisson's own outputs
(as seen by the partition). The module has a full flake-parts evaluation context
with its own `perSystem`, `imports`, etc.

## Evaluating Consumer Flakes with `callConsumerFlake`

### The pattern

For each test or example flake, `checks.nix` builds one call:

```nix
consumerPool = {
  inherit (inputs) flake-parts nixpkgs nixpkgs-lib nix-unit;
  deps = inputs.self;
  parent = self;
};
callConsumer = args: lib.caisson-core.callConsumerFlake ({ pool = consumerPool; } // args);

unitTestOutputs = callConsumer { path = self.outPath + "/tests/unit"; };
```

`callConsumerFlake` imports the directory's `flake.nix` as a plain Nix
expression and applies its `outputs` function to explicitly constructed
inputs. Each input the flake declares resolves by name: an entry in
`overrides` wins, then a `follows` chain, then the `pool`; a name that
resolves nowhere throws. Nothing is fetched and no lockfile is read or
written. The [library reference](../reference/lib.md) documents the full
signature.

The imported `flake.nix` is not a resolved flake: it has no resolved inputs, no
`outPath`, no `self`. `callConsumerFlake` supplies each piece:

- **`self`** becomes a lazy fixpoint over the outputs, mirroring normal flake
  evaluation, where `self` is always a lazy reference to the flake's own
  outputs.
- **`outPath`** is set to the evaluated directory. This matters because config
  modules use relative paths (the unit test config imports
  `../../../lib-overlays.nix`), and those resolve against `outPath`.
- **`inputs`** is attached to the result so the outputs attrset matches the
  shape of a normally resolved flake.

`overrides` carries per-flake injections. The lib-consumer-chain tests use it
to thread markers and to hand the middle flake's evaluated outputs to the
final consumer, and the example flakes use `overrides.caisson = self` so the
example consumes the current source tree.

### The `deps` mapping

In standalone mode, the test flakes declare `deps.url = "path:../dependencies"`
and use `follows` to pull inputs through it (e.g., `nixpkgs.follows = "deps/nixpkgs"`).
The `deps` input is the shared dependencies flake, and `follows` resolution means
a test flake ends up with `deps.inputs.nixpkgs`, `deps.inputs.nix-unit`, etc.

In the partition, the pool provides `deps = inputs.self`. Inside a partition
module, `inputs.self` is not plain caisson; it is caisson with an augmented
`.inputs` attrset. The partition machinery (in
`flake-parts/extras/partitions.nix`) constructs:

```nix
inputs2 = inputs // config.extraInputs // { self = self2; };
self2 = self // { inputs = inputs2; };
```

So `inputs.self` is `self2`: caisson's outputs merged with
`{ inputs = <main inputs + extra inputs> }`. This means `inputs.self.inputs.nixpkgs`,
`inputs.self.inputs.nix-unit`, etc. all resolve to the same values that
`deps.inputs.nixpkgs`, `deps.inputs.nix-unit` would in standalone mode. The
partition's augmented `self` is a valid stand-in for the dependencies flake because
its `.inputs` is a superset of the dependencies flake's inputs.

## Unit Testing with nix-unit

### A downstream composition

The unit test flake (`tests/unit/flake.nix`) composes the way a downstream
consumer that cares about its core revision does: with its own `caisson-core`
input, registering caisson's overlay files from the parent's source path.

```nix
lib = inputs.caisson-core.lib.caisson-core.mkLib {
  inherit inputs;
  baseLib = inputs.nixpkgs-lib.lib;
  libOverlays = mkLibOverlay: {
    flake-parts = mkLibOverlay (parent.outPath + "/lib-overlays/flake-parts");
  };
};

lib.caisson.mkFlake {
  configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/unit-tests;
};
```

The `parent` input is caisson's source tree, declared `flake = false`:
evaluating a flake input's value applies its outputs function, which would
force caisson's own hidden core pin inside the nix-unit sandbox, where nothing
can fetch. A source-only input carries the path and applies nothing. The
overlay files register from that path because a flake cannot reference files
outside its own source tree.

The tests are not only testing library functions in isolation; the composition
and `mkFlake` path is the same one a downstream consumer exercises, so they
verify that the framework's composition machinery works end-to-end.

### nix-unit integration

The test flake's config module (`tests/unit/configs/flake-parts/unit-tests/default.nix`)
imports the nix-unit flake-parts module:

```nix
imports = [ inputs.nix-unit.modules.flake.default ];
```

This module adds two key options:

- `flake.tests`: a nested attrset of test groups, each containing named tests
  with `{ expr; expected; }` pairs
- `perSystem.nix-unit.inputs`: the inputs to pass to nix-unit for evaluation

The config sets these:

```nix
flake.tests = import ../../../lib-overlays.nix { inherit inputs lib; };

perSystem.nix-unit = { inherit inputs; };
```

The nix-unit module generates a check derivation (`checks.<system>.nix-unit`) that
invokes the `nix-unit` binary against the test attrset, wiring each declared
input to a store path with `--override-input`; the evaluation runs inside the
build sandbox, which is why every value a test forces must be reachable
without fetching. Each `expr` is evaluated and compared to its `expected`
value.

### Test attrset structure

`tests/unit/lib-overlays.nix` returns a nested attrset where:

- Top-level keys are test groups (e.g., `libExport`, `importApply`, `mkModule`,
  `mkLibOverlay`, `mkLib`)
- Each group contains named tests as `{ expr; expected; }` pairs

The `lib` argument is the composed library from the unit test flake (which includes
the registered caisson overlays), so the tests exercise the library as it would
appear to a consumer.

## Integration Testing

### Purpose

Integration test flakes verify that caisson works correctly when consumed as a
dependency: that `mkLib`, `mkFlake`, class-keyed module registration, and
module composition behave as expected from a consumer's perspective.

### Structure

Each integration test is a standalone flake under `tests/integration/<name>/` that:

1. Takes `parent` (caisson's evaluated outputs, from the pool) as an input
2. Calls `parent.lib.caisson-core.mkLib { inherit inputs; ... }` to bootstrap
3. Uses `lib.caisson.mkFlake` to compose a flake
4. Defines a `checks.<system>.<name>` derivation that succeeds if composition
   worked

For example, `basic-composition` defines a trivial check that proves composition
succeeded:

```nix
checks.composition-success =
  pkgs.runCommand "composition-success" { }
    "echo 'composed successfully' > $out";
```

`minimal-consumer` goes further by also exercising `flakeModules.default` and
`configInfo.configName`, and verifying that the consumer's outputs include expected
attributes (`flakeModule`, `lib`). `module-class-export` tests the generic
module class system: it registers modules under synthetic classes via the
`modules` attrset, configures per-class export controls, and asserts that
enabled classes appear in `flake.modules` while disabled classes have their
module content suppressed. `lib-consumer-chain` evaluates a two-hop consumer
chain (caisson, a middle flake, a final consumer) to verify that exported
overlays and modules compose transitively.

Integration flakes read caisson through `parent`, which in the partition is
caisson's real evaluated outputs, so unlike the unit tests they exercise the
export projections exactly as a published consumer would.

## Shared Dependencies Flake

`tests/dependencies/flake.nix` declares the development-time inputs shared by the test and example flakes:

```nix
inputs.caisson-core.url = "github:nix-caisson/caisson-core";
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
inputs.flake-parts.url = "github:hercules-ci/flake-parts";
inputs.nix-unit.url = "github:nix-community/nix-unit";
inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
```

Its `outputs` is empty. It exists for three reasons:

1. **Partition input source:** The checks and formatter partitions load it
   through `partitionExtraInputs` to pull these inputs into their evaluation
   without adding them to caisson's main `flake.nix`.

2. **`follows` target for test flakes:** The standalone test flakes use
   `nixpkgs.follows = "deps/nixpkgs"` (etc.) to share the same locked versions
   as the dependencies flake, avoiding duplicate fetches when evaluating
   standalone.

3. **Single lockfile:** All development dependencies are locked in
   `tests/dependencies/flake.lock`, making version management straightforward.
   The test flakes' own lockfiles are gitignored; standalone use generates
   them locally, and the `follows` wiring resolves them to the same versions.

The dependencies flake uses `follows` internally to deduplicate transitive inputs
(e.g., `inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs"`).

## Example Flakes

The checks partition also wires in example flakes (e.g., `examples/literate-flake/`)
through the same `callConsumer` calls, with `overrides.caisson = self`. These are
both documentation and regression tests: if the example stops evaluating,
`nix flake check` fails.

## Complete Check Inventory

The checks partition merges outputs from all test and example flakes into a single
`checks.<system>` attrset. As of this writing, `nix flake check` runs:

| Check | Source | What it verifies |
|---|---|---|
| `nix-unit` | `tests/unit/` | Library function correctness |
| `composition-success` | `tests/integration/basic-composition/` | Basic flake composition |
| `minimal-consumer-success` | `tests/integration/minimal-consumer/` | Minimal consumption pattern |
| `minimal-consumer-all-outputs` | `checks.nix` (inline) | Consumer exposes `flakeModule` and `lib` |
| `module-class-export-success` | `tests/integration/module-class-export/` | Class-keyed module export and disable |
| `lib-consumer-chain-success` | `tests/integration/lib-consumer-chain/` | Transitive consumption through a middle flake |
| `literate-flake-default` | `examples/literate-flake/` | Example default package builds |
| `literate-flake-greeting` | `examples/literate-flake/` | Example greeting package builds |
| `debug-disabled` | `checks.nix` (inline) | `self.debug` is not exposed in production |
| `eval-weight` | `checks.nix` + `tests/eval-weight/` | Framework evaluation cost held to committed ceilings ([guide](../eval-weight.md)) |
