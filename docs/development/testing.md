# caisson Testing

If you need to modify the test infrastructure itself (e.g., adding a new test
flake, changing how checks are wired, or debugging the evaluation of the
checks configuration), see [testing-architecture.md](testing-architecture.md) for how the
plumbing works.

## Unit Testing

- **Framework:** nix-unit, integrated into flake checks via flake-parts.
- **Scope:** Pure functions, library overlays, and module logic.
- **Location:** `tests/unit/`
- **Canonical Pattern:** See `tests/unit/lib-overlays.nix` for the standard test structure.
- **Execution:**
  ```bash
  # Run all checks (includes unit tests)
  nix flake check

  # Run a specific check
  nix build .#checks.<system>.<checkName> -L
  ```

## Pinned-World Suite

- **Scope:** caisson composed with concrete pinned versions of the upstream
  world (nixpkgs, home-manager, colmena, disko, nix-darwin, hjem,
  terranix, system-manager) and exercised end to end: a home-manager
  configuration, a NixOS configuration with home-manager configurations
  declared inside it, a colmena hive, disk layouts with the NixOS
  configurations installed onto them, a nix-darwin configuration
  evaluated for aarch64-darwin with and without a home-manager
  configuration and a hjem configuration inside it, hjem configurations
  declared at the top of the flake and inside a NixOS configuration, a
  terranix and a system-manager configuration, and the composition
  guarantees of the real exported overlays. The `hjem-system` check
  builds the manifest file of the hjem configuration inside the NixOS
  configuration, which checks it against hjem's schema, and the units
  that activate it, which runs shellcheck on their scripts. The
  nix-darwin configurations of the suite are also the
  check for aarch64-darwin, `checks.aarch64-darwin.darwin-system`, which the
  `darwin-build` job of the check workflow builds on a macOS runner. Every upstream expectation caisson relies on is a probe here.
- **Location:** `tests/pinned-world/default.nix`; the pins in
  `tests/dependencies/flake.lock`.
- **Mechanism:** The checks configuration forces the suite's `summary` at
  evaluation time as the `pinned-world` check, so `nix flake check` runs it
  at the committed pins and a change to caisson is judged against the last
  known good world. The `drift` workflow runs daily on `main`, advances the
  pins in the working tree without committing, and builds the same check
  against today's upstreams; its badge is on the README. Red there means an
  upstream moved and broke an expectation, and the committed pins move in
  the commit that fixes it.
- **Execution:**
  ```bash
  nix build .#checks.<system>.pinned-world -L

  # Against today's upstreams, the way the drift workflow does:
  nix flake update --flake ./tests/dependencies
  nix flake update caisson-core flake-parts nixpkgs-lib
  nix build .#checks.<system>.pinned-world -L
  git checkout -- tests/dependencies/flake.lock flake.lock
  ```

## Argument Errors (Trace Shape)

- **Scope:** The argument error of every entry point (`mkConfiguration`,
  its `WithEcosystemArgs` variant, `nixos.mkConfigurationFull`, the colmena
  node constructors) is Nix's function-argument error, raised at the
  call site: between `error:` and the message stands the call site and
  no frame of caisson.
- **Location:** `tests/argument-errors/check.sh`
- **Mechanism:** nix-unit matches error messages and cannot see frames, so
  the script runs the real evaluator (`nix eval`) against each entry point
  with a wrong call and reads the trace. The `argument-errors` check runs
  it in the sandbox over a library composed from store paths.
- **Execution against the flake's library, from a checkout:**
  ```bash
  tests/argument-errors/check.sh \
    'let f = builtins.getFlake "path:'"$PWD"'"; in f.lib' --impure
  ```

## Deferred Configuration Errors (Message Text)

- **Scope:** The text of the errors of deferred configurations and the
  NixOps4 integrations. A tool tells an arg it lacks from a failure by
  `caisson-deferred: needs <path>`, and `builtins.tryEval` in the
  pinned-world suite sees only that the evaluation failed.
- **Location:** `tests/deferred-errors/check.sh` and its cases in
  `tests/deferred-errors/cases.nix`.
- **Mechanism:** the script runs `nix eval` on each case and looks for
  the line of text in the message that the case names. The `deferred-errors` check
  runs it in the sandbox over the library of the `argument-errors`
  check and the NixOps4 source.
- **Execution against the flake's library, from a checkout:**
  ```bash
  tests/deferred-errors/check.sh \
    'let f = builtins.getFlake "path:'"$PWD"'"; in f.lib' \
    <path of the NixOps4 source> --impure
  ```

## Volatile Checks (Builds in the Local Store)

- **Scope:** The derivation `lib.caisson.mkVolatileCheck` returns, built:
  a check whose program passes writes its pass marker at the output
  path its derivation declares, building it again with `--rebuild`
  keeps the marker, and a check whose program fails leaves no marker in
  the store. The pinned-world suite holds what evaluation shows of the
  derivation: its name, its fixed output and its `drvAttrs`.
- **Location:** `tests/volatile-checks/check.sh` and the checks it
  builds in `tests/volatile-checks/default.nix`.
- **Mechanism:** the script runs `nix build` on each check and reads the
  store afterwards with `nix path-info`. A check of `nix flake check` is
  a build and cannot do either, so the `volatile-checks` job of the
  check workflow runs the script on the runner.
- **Execution, from a checkout:**
  ```bash
  tests/volatile-checks/check.sh
  ```

## Integration Testing (Test Flakes)

- **Scope:** Module composition, end-to-end evaluation, and build success.
- **Location:** Sub-directories within `tests/integration/` (e.g., `tests/integration/basic-composition/flake.nix`).
- **Mechanism:** Nested Nix flakes that import caisson as an input and verify that modules behave as expected when consumed.
- **Canonical Pattern:** See `tests/integration/basic-composition/` for the standard structure.

## Test Coverage

- Every library function and major module logic path must have corresponding unit tests.
- Major features and module changes must be verified by a corresponding test flake.
- Use nix-unit coverage tools to ensure new functions are exercised by tests.
