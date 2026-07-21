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

## Integration Testing (Test Flakes)

- **Scope:** Module composition, end-to-end evaluation, and build success.
- **Location:** Sub-directories within `tests/integration/` (e.g., `tests/integration/basic-composition/flake.nix`).
- **Mechanism:** Nested Nix flakes that import caisson as an input and verify that modules behave as expected when consumed.
- **Canonical Pattern:** See `tests/integration/basic-composition/` for the standard structure.

## Test Coverage

- Every library function and major module logic path must have corresponding unit tests.
- Major features and module changes must be verified by a corresponding test flake.
- Use nix-unit coverage tools to ensure new functions are exercised by tests.
