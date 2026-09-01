# Testing Architecture

This document explains how caisson's tests are wired into the flake's check
infrastructure. The setup is non-obvious: test flakes live as independent
`flake.nix` files in the source tree but are not evaluated as normal flakes.
Instead, they are imported as raw Nix expressions inside a flake-parts partition,
with manually constructed inputs and lazy circular self-references.

> **Nix version note (2.31.3, March 2026):** The raw-import-and-wire pattern
> exists because the Nix flake machinery cannot natively evaluate nested flakes
> within a parent flake's evaluation, and `builtins.getFlake` cannot handle paths
> in pure mode. If future Nix versions add first-class support for nested flake
> evaluation or lift the pure-mode path restriction, much of this manual wiring
> could be replaced with direct flake calls.

For commands and test conventions, see [testing.md](./testing.md).

## Overview

All checks are produced by the **checks partition**
(`configs/flake-parts/partitions/checks.nix`). This partition:

1. Pulls in development-time dependencies via `extraInputsFlake` pointing to
   `tests/dependencies/flake.nix`
2. Imports each test flake as a raw Nix expression
3. Manually constructs the input attrset each test flake expects
4. Calls the test flake's `outputs` function and merges the resulting
   `checks.<system>` into caisson's top-level `checks` output

The partition mechanism (`partitionedAttrs.checks = "checks"`) causes flake-parts
to replace the main evaluation's `checks` with the partition's `checks`, so
`nix flake check` runs everything the partition defines.

## The Checks Partition

### The reason for the partition

flake-parts partitions allow a flake to declare outputs that depend on inputs not
listed in the main `flake.nix`. caisson's main inputs are only `nixpkgs-lib` and
`flake-parts`; it deliberately avoids depending on full `nixpkgs` or development
tools like `nix-unit`. The checks partition brings in these heavier dependencies
without polluting the main flake's input set or forcing consumers to fetch them.

### How `extraInputsFlake` works

The partition declares:

```nix
extraInputsFlake = ../../../tests/dependencies;
```

flake-parts resolves this path using its vendored `flake-compat` (not
`builtins.getFlake`, which cannot handle paths in pure evaluation mode). The
resolved flake's `inputs` are merged into the partition's `inputs` module argument.
This is how `nixpkgs`, `nix-unit`, `treefmt-nix`, etc. become available inside the
partition module without being declared in the main `flake.nix`.

Source: the upstream `flake-parts/extras/partitions.nix` `get-flake` function.

### Partition module structure

Inside the partition module, `inputs` contains both the main flake's inputs and the
extra inputs from the dependencies flake. `self` refers to caisson's own outputs
(as seen by the partition). The module has a full flake-parts evaluation context
with its own `perSystem`, `imports`, etc.

## The Raw-Import-and-Wire Pattern

### Raw imports instead of normal flake evaluation

The test flakes under `tests/unit/` and `tests/integration/` are standalone
`flake.nix` files, but their lockfiles are gitignored, not committed.
When used standalone (e.g., `cd tests/unit && nix flake check`), Nix generates a
local lockfile on first use and evaluates normally. Because all inputs use `follows`
pointing at the shared dependencies flake, the generated lockfile resolves to the
same versions.

Inside the checks partition, there is no mechanism to trigger normal flake
evaluation of a nested flake. `extraInputsFlake` resolves one dependency flake;
it's not a general-purpose nested-flake evaluator. The partition needs to reach into
the test flake's outputs to extract `checks`, which means it needs to call the
test flake's `outputs` function directly. No lockfiles are generated or consulted
in this path; inputs are supplied directly by the partition.

### How it works

For each test flake, `checks.nix` follows this pattern:

```nix
# 1. Import the flake.nix as a plain Nix expression
unitTestFlake = import (self.outPath + "/tests/unit/flake.nix");

# 2. Manually construct the inputs the outputs function expects
unitTestInputs = {
  inherit (inputs) flake-parts nix-unit nixpkgs nixpkgs-lib;
  deps = inputs.self;
  parent = self;
  self = unitTestOutputs;   # lazy circular reference
};

# 3. Call outputs and patch the result to look like a resolved flake
unitTestOutputs = unitTestFlake.outputs unitTestInputs // {
  inputs = unitTestInputs;
  outPath = self.outPath + "/tests/unit";
};
```

Step 1 bypasses flake evaluation entirely: `import` just loads the file as a Nix
attrset. The imported value is not a resolved flake: it has no resolved inputs, no
`outPath`, no `self`.

Step 2 maps the partition's resolved inputs onto the names the test flake expects.
The key mappings for the unit test flake are:

| Test flake input | Partition value | Why |
|---|---|---|
| `flake-parts` | `inputs.flake-parts` | From dependencies flake |
| `nix-unit` | `inputs.nix-unit` | From dependencies flake |
| `nixpkgs` | `inputs.nixpkgs` | From dependencies flake |
| `nixpkgs-lib` | `inputs.nixpkgs-lib` | From dependencies flake |
| `deps` | `inputs.self` | See "The `deps` mapping" below |
| `parent` | `self` | caisson itself, as seen by the partition |
| `self` | `unitTestOutputs` | Circular (explained below) |

Integration test flakes use the same pattern with simpler input sets (no `nix-unit`,
no `nixpkgs-lib`).

### The `deps` mapping

In standalone mode, the unit test flake declares `deps.url = "path:../dependencies"`
and uses `follows` to pull inputs through it (e.g., `nixpkgs.follows = "deps/nixpkgs"`).
The `deps` input is the shared dependencies flake, and `follows` resolution means
the test flake ends up with `deps.inputs.nixpkgs`, `deps.inputs.nix-unit`, etc.

In the raw-import path, `follows` doesn't apply, because there's no lockfile resolution.
The direct inputs (`nixpkgs`, `nix-unit`, etc.) are provided explicitly in
`unitTestInputs`. But `deps` still needs to be provided because the test flake's
`outputs` function receives the full `inputs` attrset (via `inputs@{ ... }`), and
that attrset is passed onward to `parent.lib.caisson-core.mkLib { inherit inputs; ... }` and to the
nix-unit module via `perSystem.nix-unit = { inherit inputs; }`. If any code path
accesses `inputs.deps`, it must resolve to something sensible.

The partition provides `deps = inputs.self`. Inside a partition module, `inputs.self`
is not plain caisson; it's caisson with an augmented `.inputs` attrset. The
partition machinery (in `flake-parts/extras/partitions.nix`) constructs:

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

### Circular self-reference

The line `self = unitTestOutputs` creates a circular dependency:
`unitTestInputs` references `unitTestOutputs`, and `unitTestOutputs` is defined as
`unitTestFlake.outputs unitTestInputs // { ... }`. This works because Nix is lazy:
`self` is a thunk that is only forced when the test flake's `outputs` function
actually accesses it, at which point the value has been defined.

This mirrors normal flake evaluation, where `self` is always a lazy reference to
the flake's own outputs.

### `outPath` patching

```nix
outPath = self.outPath + "/tests/unit";
```

A normally-evaluated flake has an `outPath` set by the Nix flake machinery to the
store path of the flake's source tree. A raw-imported `flake.nix` has no such
attribute. The partition patches it manually to point at the correct subdirectory
within caisson's source tree.

This is critical because the test flake's config module uses relative paths. For
example, the unit test config imports `../../../lib-overlays.nix`, which resolves
relative to the `outPath`. Without patching, these paths would fail.

`inputs = unitTestInputs` is also attached so that the outputs attrset includes
`.inputs`, matching the shape of a normally-resolved flake.

## Unit Testing with nix-unit

### Self-hosting

The unit test flake (`tests/unit/flake.nix`) bootstraps itself using caisson's own
framework:

```nix
lib = parent.lib.caisson-core.mkLib {
  inherit inputs;
  libOverlays = _mkLibOverlay: {
    flake-parts = parent.libOverlays.flake-parts;
  };
};

lib.caisson.mkFlake {
  configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/unit-tests;
};
```

The `parent` input is caisson itself. By using `parent.lib.caisson-core.mkLib` and
`lib.caisson.mkFlake`, the test flake exercises the same module composition path
that downstream consumers use. This means the tests are not just testing library
functions in isolation; they verify that the framework's composition machinery
works end-to-end.

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
flake.tests = import ../../../lib-overlays.nix { inherit lib; };

perSystem.nix-unit = { inherit inputs; };
```

The nix-unit module generates a check derivation (`checks.<system>.nix-unit`) that
invokes the `nix-unit` binary against the test attrset. Each `expr` is evaluated and
compared to its `expected` value.

### Test attrset structure

`tests/unit/lib-overlays.nix` returns a nested attrset where:

- Top-level keys are test groups (e.g., `libExport`, `importApply`, `mkModule`,
  `mkLibOverlay`, `mkLib`)
- Each group contains named tests as `{ expr; expected; }` pairs

The `lib` argument is the composed library from the unit test flake (which includes
all caisson overlays), so the tests exercise the library as it would appear to a
consumer.

## Integration Testing

### Purpose

Integration test flakes verify that caisson works correctly when consumed as a
dependency: that `mkLib`, `mkFlake`, class-keyed module registration, and
module composition behave as expected from a consumer's perspective.

### Structure

Each integration test is a standalone flake under `tests/integration/<name>/` that:

1. Takes `parent` (caisson) as an input
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
attributes (`flakeModule`, `lib`).

`module-class-export` tests the generic module class system: it registers modules
under synthetic classes via the `modules` attrset, configures per-class export
controls, and asserts that enabled classes appear in `flake.modules` while disabled
classes have their module content suppressed.

### Wiring in `checks.nix`

Integration tests use the same raw-import-and-wire pattern as unit tests, with
simpler inputs:

```nix
integrationInputs = {
  inherit (inputs) flake-parts nixpkgs;
  deps = inputs.self;
  self = integrationOutputs;
  parent = self;
};
```

No `nix-unit` or `nixpkgs-lib` is needed. The `deps` mapping and `self` circular
reference follow the same principles described above.

Integration test outputs don't require `outPath` patching because their config
modules don't use paths that depend on it.

Like the unit test wiring, integration tests provide `deps = inputs.self` so that
the full `inputs` attrset passed to `mkLib` matches the shape of a standalone
evaluation (see "The `deps` mapping" above for why this works).

## Shared Dependencies Flake

`tests/dependencies/flake.nix` declares the development-time inputs shared by the test and example flakes:

```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
inputs.flake-parts.url = "github:hercules-ci/flake-parts";
inputs.nix-unit.url = "github:nix-community/nix-unit";
inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
```

Its `outputs` is empty. It exists for three reasons:

1. **Partition input source:** The checks and formatter partitions use
   `extraInputsFlake = tests/dependencies` to pull these inputs into their
   evaluation without adding them to caisson's main `flake.nix`.

2. **`follows` target for test flakes:** The standalone test flakes use
   `nixpkgs.follows = "deps/nixpkgs"` (etc.) to share the same locked versions
   as the dependencies flake, avoiding duplicate fetches when evaluating
   standalone.

3. **Single lockfile:** All development dependencies are locked in
   `tests/dependencies/flake.lock`, making version management straightforward.

The dependencies flake uses `follows` internally to deduplicate transitive inputs
(e.g., `inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs"`).

## Example Flakes

The checks partition also wires in example flakes (e.g., `examples/literate-flake/`)
using the same raw-import pattern. These are both documentation and regression
tests: if the example stops evaluating, `nix flake check` fails.

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
| `literate-flake-default` | `examples/literate-flake/` | Example default package builds |
| `literate-flake-greeting` | `examples/literate-flake/` | Example greeting package builds |
| `debug-disabled` | `checks.nix` (inline) | `self.debug` is not exposed in production |
| `treefmt` | treefmt-nix module | All Nix files are formatted |
