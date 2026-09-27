# caisson Testing

If you need to modify the test infrastructure itself (e.g., adding a new test
flake, changing how checks are wired, or debugging partition-level evaluation
issues), see [testing-architecture.md](testing-architecture.md) for how the
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
  world (nixpkgs, home-manager, colmena, terranix, system-manager) and
  exercised end to end: a home configuration, a NixOS system with the
  home-manager adapter, a colmena hive, a terranix and a system-manager
  configuration, and the composition guarantees of the real exported
  overlays. Every upstream expectation caisson relies on is a probe here.
- **Location:** `tests/pinned-world/default.nix`; the pins in
  `tests/dependencies/flake.lock`.
- **Mechanism:** The checks partition forces the suite's `summary` at
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
  nix build .#checks.<system>.pinned-world -L
  git checkout -- tests/dependencies/flake.lock
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
