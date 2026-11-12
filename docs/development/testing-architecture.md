# Testing Architecture

This document explains how caisson's tests are wired into the flake's check
infrastructure. The setup is non-obvious: test flakes live as independent
`flake.nix` files in the source tree but are not evaluated by the Nix flake
machinery. Instead, the checks configuration, a flake-parts configuration
declared inside caisson's flake, evaluates each test flake from source with
`lib.caisson.callConsumerFlake`, which wires inputs explicitly.

> **Nix version note (2.31.3, March 2026):** The evaluate-from-source pattern
> exists because the Nix flake machinery cannot natively evaluate nested flakes
> within a parent flake's evaluation, and `builtins.getFlake` cannot handle paths
> in pure mode. If future Nix versions add first-class support for nested flake
> evaluation or lift the pure-mode path restriction, this wiring could be
> replaced with direct flake calls.

For commands and test conventions, see [testing.md](./testing.md).

## Overview

All checks are declared in the **checks configuration**
(`configs/flake/checks`), a flake-parts configuration that the caisson top in
`configs/flake/caisson` declares under
`caisson.flake-parts.configurations.checks`. The checks configuration:

1. Adds the development-time dependencies of `tests/dependencies` to the
   dependencies of the caisson top, read by the flake-compat pin reader,
   `lib.caisson.pins.flake-compat`
2. Evaluates each test and example flake from source with
   `callConsumerFlake`, resolving the flake's declared inputs from a shared
   pool
3. Defines the resulting `checks.<system>` attrsets, plus a few inline checks
   and the `eval-weight` check, as its `checks` under `perSystem`

The caisson top gathers the checks of every configuration declared inside it
into its `checks` output, so `nix flake check` runs everything the checks
configuration defines.

## The Checks Configuration

### The reason for the checks configuration

caisson's flake declares only the inputs its configurations are composed with
(caisson-core, nixpkgs-lib, flake-parts), and it deliberately avoids depending on
full `nixpkgs` or development tools like `nix-unit`. Every flake that uses caisson
locks the inputs of caisson's `flake.nix`. The checks configuration brings in the
heavier dependencies of the checks without adding them to caisson's `flake.nix`.

### How the extra dependencies load

The caisson top declares the checks configuration with the dependencies of
`tests/dependencies`:

```nix
caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
  inherit (lib.caisson.pins.flake-compat ../../../tests/dependencies) dependencies;
};
caisson.flake-parts.exported = _: { };
```

`pins.flake-compat` resolves the lock of the dependencies flake the way
flake-compat does and returns its inputs as pinned dependencies, each flake
input with its outputs, without evaluating the dependencies flake itself. It
does not go through `builtins.getFlake`, which cannot handle paths in pure
evaluation mode, and it stays safe under read-only evaluation
(`nix flake check --no-build`).

The flake-parts integration adds those dependencies to the dependencies of the
caisson top, and the `inputs` of the checks configuration hold both. For a name
that `flake.lock` pins as well (caisson-core, flake-parts, nixpkgs-lib),
`inputs` hold the pin of `flake.lock`, and the manifest of the checks
configuration records the entry of `tests/dependencies` under
`shadowedDependencies`. The entry of `tests/dependencies` still serves the
`follows` lines of `tests/dependencies/flake.nix`, which can name only the
inputs of that file. So the checks evaluate caisson with the pins every flake
that uses caisson gets.

The caisson top gathers the checks of the checks configuration whatever its
`caisson.flake-parts.exported` selector passes up. The selector `_: { }` passes
the checks configuration up to nothing, so a flake that lists caisson in
`projects` reads the exports of caisson without evaluating the checks
configuration or reading `tests/dependencies`. The `checks-evaluation-consumer`
check shows it, with a producer whose checks configuration has dependencies
that throw when they are read.

### Checks configuration module structure

Inside the checks configuration, `inputs` holds the dependencies of the caisson
top and those of `tests/dependencies`. `self` is the flake of the checks
configuration, and `self.outPath` is caisson's source tree. The checks read
caisson itself as `caisson`, the flake of caisson evaluated from that source
tree with `callConsumerFlake` over `inputs`, as a flake that lists caisson as
an input reads it. The module has a full flake-parts evaluation context with
its `perSystem`, `imports`, etc. Its `containerTests` and `nestedVmTests`
outputs are not checks: the caisson top publishes them under the same names,
and the workflows build them by name.

## Evaluating Consumer Flakes with `callConsumerFlake`

### The pattern

For each test or example flake, `configs/flake/checks` builds a call:

```nix
consumerPool = {
  inherit (inputs) flake-parts nixpkgs nixpkgs-lib nix-unit;
  deps = self;
  parent = caisson;
};
callConsumer = args: lib.caisson.callConsumerFlake ({ pool = consumerPool; } // args);

unitTestOutputs = callConsumer { path = self.outPath + "/tests/unit"; };
```

`callConsumerFlake` imports the directory's `flake.nix` as a plain Nix
expression and applies its `outputs` function to explicitly constructed
inputs. Each input the flake declares resolves by name: an entry in
`overrides` wins, then a `follows` chain, then the `pool`; a name that
resolves nowhere throws. Nothing is fetched and no lockfile is read or
written. The [library reference](https://nix-caisson.github.io/docs/reference/lib.html) documents the full
signature.

The imported `flake.nix` is not a resolved flake: it has no resolved inputs, no
`outPath`, no `self`. `callConsumerFlake` supplies each piece:

- **`self`** becomes a lazy fixpoint over the outputs, as in normal flake
  evaluation, where `self` is always a lazy reference to the flake's
  outputs.
- **`outPath`** is set to the evaluated directory. This matters because config
  modules use relative paths (the unit test config imports
  `../../../lib-overlays.nix`), and those resolve against `outPath`.
- **`inputs`** is attached to the result so the outputs attrset matches the
  shape of a normally resolved flake.

`overrides` carries per-flake injections. The lib-consumer-chain tests use it
to thread markers and to hand the middle flake's evaluated outputs to the
final consumer, and the example flakes use `overrides.caisson = caisson` so the
example consumes the current source tree.

### The `deps` mapping

In standalone mode, the test flakes declare `deps.url = "path:../dependencies"`
and use `follows` to pull inputs through it (e.g., `nixpkgs.follows = "deps/nixpkgs"`).
The `deps` input is the shared dependencies flake, and `follows` resolution means
a test flake ends up with `deps.inputs.nixpkgs`, `deps.inputs.nix-unit`, etc.

In the checks configuration, the pool provides `deps = self`, the flake of the
checks configuration, whose `inputs` are the inputs of the checks configuration
and whose out path is caisson's source tree. `callConsumerFlake` resolves
`follows = "deps/nixpkgs"` to `deps.inputs.nixpkgs`, so `deps/nixpkgs`,
`deps/nix-unit` and the rest resolve to the inputs of the checks
configuration. Those are the inputs of the dependencies flake, except
the names `flake.lock` pins as well, which resolve to the pins of `flake.lock`.

## Unit Testing with nix-unit

### A downstream composition

The unit test flake (`tests/unit/flake.nix`) composes the way a downstream
consumer that pins its caisson-core revision does: with a `caisson-core`
input of the test flake, registering caisson's overlay and module files from the parent's
source path with the directory readers.

```nix
core = inputs.caisson-core.lib.caisson-core;
lib = core.mkLib {
  inherit (core.pins.flake inputs) dependencies root;
  defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib.outPath;
  modules = lib: lib.caisson-core.mkModules (parent.outPath + "/modules");
  libOverlays = lib: lib.caisson-core.mkLibOverlays (parent.outPath + "/lib-overlays");
};

lib.caisson.flake-parts.mkTopConfiguration {
  configModule = lib.caisson.flake-parts.mkModule ./configs/flake/unit-tests;
};
```

The `parent` input is caisson's source tree, declared `flake = false`:
evaluating a flake input's value applies its outputs function, which would
force the `caisson-core` input of caisson inside the nix-unit sandbox, where
nothing can fetch. A source-only input carries the path and applies nothing. The
overlay files register from that path because a flake cannot reference files
outside its source tree, and the modules register with them: an overlay
registered from its file reads the registry of the composition that
registered it (the `core` of its class, for example), so the two go together.

The tests are not only testing library functions in isolation; the composition
and `lib.caisson.flake-parts.mkTopConfiguration` path is the same path a downstream consumer exercises, so they
verify that the framework's composition machinery works end-to-end.

### nix-unit integration

The test flake's config module (`tests/unit/configs/flake/unit-tests/default.nix`)
imports the nix-unit flake-parts module:

```nix
imports = [ inputs.nix-unit.modules.flake.default ];
```

This module adds these key options:

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
dependency: that `mkLib`, `lib.caisson.flake-parts.mkTopConfiguration`, class-keyed module registration, and
module composition behave as expected from a consumer's perspective.

### Structure

Each integration test is a standalone flake under `tests/integration/<name>/` that:

1. Takes `parent` (caisson's evaluated outputs, from the pool) as an input
2. Calls `parent.lib.caisson-core.mkLib { inherit (parent.lib.caisson-core.pins.flake inputs) dependencies root; ... }` to bootstrap
3. Uses `lib.caisson.flake-parts.mkTopConfiguration` to compose a flake
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
the `lib` flake output. It asserts that the `lib` output holds the lib overlay
of the flake under the `name` the composition declares on `mkLib`, and the
manifest of the flake at `lib.caisson-core.evalManifest`. `module-class-export` tests the generic
module class system: it registers modules under synthetic classes via the
`modules` attrset, configures per-class export controls, and asserts that
enabled classes appear in `flake.modules` while disabled classes have their
module content suppressed. `lib-consumer-chain` evaluates a consumer
chain (caisson, a middle flake, a final consumer) to verify that exported
overlays and modules compose transitively.

Integration flakes read caisson through `parent`, which in the checks
configuration is the flake of caisson evaluated from its source tree over the
pins of `flake.lock`, so unlike the unit tests they exercise the exported
outputs exactly as a published consumer would.

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

Its `outputs` is empty. It exists for these reasons:

1. **Source of the extra dependencies:** The checks configuration and the
   formatter partition read it through `pins.flake-compat` to bring these
   inputs into their evaluation without adding them to caisson's main
   `flake.nix`.

2. **`follows` target for test flakes:** The standalone test flakes use
   `nixpkgs.follows = "deps/nixpkgs"` (etc.) to share the same locked versions
   as the dependencies flake, avoiding duplicate fetches when evaluating
   standalone.

3. **Single lockfile:** All development dependencies are locked in
   `tests/dependencies/flake.lock`, making version management straightforward.
   The test flakes' lockfiles are gitignored; standalone use generates
   them locally, and the `follows` wiring resolves them to the same versions.

The dependencies flake uses `follows` internally to deduplicate transitive inputs
(e.g., `inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs"`).

## Example Flakes

The checks configuration also wires in example flakes (e.g., `examples/literate-flake/`)
through the same `callConsumer` calls, with `overrides.caisson = caisson`. These are
both documentation and regression tests: if the example stops evaluating,
`nix flake check` fails.

## Complete Check Inventory

The checks configuration defines the checks of all test and example flakes in
its `checks.<system>` attrset, and the caisson top gathers them. As of this
writing, `nix flake check` runs:

| Check | Source | What it verifies |
|---|---|---|
| `nix-unit` | `tests/unit/` | Library function correctness |
| `composition-success` | `tests/integration/basic-composition/` | Basic flake composition |
| `minimal-consumer-success` | `tests/integration/minimal-consumer/` | Minimal consumption pattern |
| `minimal-consumer-all-outputs` | `configs/flake/checks` (inline) | Consumer exposes `flakeModule` and `lib` |
| `module-class-export-success` | `tests/integration/module-class-export/` | Class-keyed module export and disable |
| `lib-consumer-chain-success` | `tests/integration/lib-consumer-chain/` | Transitive consumption through a middle flake |
| `pkg-overlays-registry-producer` | `tests/integration/pkg-overlays-registry/producer/` | A package set applies the project `default` package overlay and its imports once; the `pkgOverlays` and `overlays` outputs carry the local entries; entries caisson contributed through `projects` are not exported by default |
| `pkg-overlays-registry-consumer` | `tests/integration/pkg-overlays-registry/consumer/` | The consumer package sets apply both defaults, a shared import once, and a named entry only where selected; a project entry leaves only when a selector names it |
| `literate-flake-default` | `examples/literate-flake/` | Example default package builds |
| `literate-flake-greeting` | `examples/literate-flake/` | Example greeting package builds |
| `debug-disabled` | `configs/flake/checks` (inline) | caisson's flake publishes no `debug` output |
| `checks-evaluation-consumer` | `tests/integration/checks-evaluation/` | A consumer reads the exports of a producer whose checks configuration is declared with dependencies that throw when they are read, and the producer evaluates neither that configuration nor those dependencies; the `checks` output of the producer reads them and throws. The checks configuration declares the checks of the consumer with `caisson.checks.checks-evaluation.top` |
| `pinned-world` | `configs/flake/checks` + `tests/pinned-world/` | caisson composed with the pinned upstream world (nixpkgs, home-manager, colmena, disko, nix-darwin, hjem, terranix, system-manager) evaluates end to end; the `drift` workflow runs the same check against advanced pins |
| `hjem-system` | `configs/flake/checks` + `tests/hjem-system/` | The manifest file of a hjem configuration inside a NixOS configuration builds, which checks it against hjem's schema with `cue vet`, and so do the units that activate it, which runs shellcheck on their scripts |
| `darwin-system` (aarch64-darwin) | `configs/flake/checks` + `tests/darwin-system/` | The nix-darwin configurations of the pinned-world suite, declared through the darwin integration, build: the bare nix-darwin configuration, and the nix-darwin configuration with a home-manager configuration and a hjem configuration inside it; the `darwin-build` job of the check workflow builds them on a macOS runner |
| `drift-message` | `configs/flake/checks` + `tests/drift-message/` | The drift check of a configuration prints its warning, with the text quoted for the shell, when the marker of the configuration above differs |
| `activation-vm` | `configs/flake/checks` + `tests/activation-vm/` | A NixOS VM switched between two versions and back activates the Nix profiles, the home-manager configurations and the hjem configurations declared inside it, through the units of each, and puts a profile changed by hand back |
| `nixos-test-vm` | `configs/flake/checks` + `tests/nixos-test-vm/` | A NixOS test declared through the nixos-test integration inside a NixOS configuration runs in a VM. The test takes the module registered under its name, and its node writes the host name it reads from the NixOS configuration the test is declared inside |
| `user-packages-vm` | `configs/flake/checks` + `tests/user-packages-vm/` | A NixOS VM installs the packages of the home-manager configurations that set `caisson.useUserPackages` in `/etc/profiles/per-user/<user>`. Each switch between two versions, and a boot, changes those packages, also for a user who has no home directory yet. The activation of each such home-manager configuration links its files and records the generations that `home-manager generations` lists. A home-manager configuration without the option installs its packages into `~/.nix-profile` |
| `nestedVmTests.x86_64-linux.microvm-host-vm`, built by name | `configs/flake/checks` + `tests/microvm-host-vm/` | A guest of a caisson-microvm configuration on cloud-hypervisor, on nested KVM, which the host runs through caisson's `microvm-host` NixOS module and the units of microvm.nix's host module: after `systemctl start microvm@probe.service` the unit is active, and the guest answers on its vsock port through the socket of its hybrid vsock. On a CI runner, which is itself a VM, the guest is three levels deep and does not boot within the start timeout, so no workflow builds it. We recommend building it by name on a machine with KVM before merging a change to `microvm-host` or the microvm integrations: `nix build -L '.#nestedVmTests.x86_64-linux.microvm-host-vm'` |
| `system-manager-vm-<distribution>` | `configs/flake/checks` + `tests/system-manager/vm.nix` | A system-manager configuration, activated through sequences of changes in a VM of Ubuntu 22.04 or Debian 12 booted from the cloud image of the distribution, applies its profiles, its home-manager configurations and its hjem configuration, and a home-manager configuration activated by hand for another version warns of the drift |
| `containerTests.x86_64-linux.system-manager-<distribution>`, built by name | `configs/flake/checks` + `tests/system-manager/container.nix` | The same sequences in a container of each distribution of `tests/system-manager/container-distros.nix`; the container needs `auto-allocate-uids`, so the `system-manager-container` job of the check workflow builds each by name |
| `argument-errors` | `configs/flake/checks` + `tests/argument-errors/` | The argument error of every entry point comes from Nix itself, raised at the call site with no frame of caisson |
| `deferred-errors` | `configs/flake/checks` + `tests/deferred-errors/` | The errors of deferred configurations and the NixOps4 integrations carry their text: `caisson-deferred: needs <path>` with the member path from the root, and the errors that refuse members or outputs named from outputs, a name declared as composite and resource, and a second root |
| `nixops4-discovery` | `configs/flake/checks` + `tests/nixops4-discovery/` | The discovery program of a NixOps4 root builds, with one state resource and with two, and prints, from recorded state dumps, the output values at the paths the root names in `argsNeeded` |
| `eval-weight` | `configs/flake/checks` + `tests/eval-weight/` | Framework evaluation cost held to committed ceilings ([guide](https://nix-caisson.github.io/docs/eval-weight.html)) |
