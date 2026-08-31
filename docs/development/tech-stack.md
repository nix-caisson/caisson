# Technology Stack

## Core Technologies

- **Nix:** The primary functional programming language used for defining the framework and its components.
- **flake-parts:** The foundational framework for building flakes, providing the module system architecture.
- **nixpkgs-lib:** caisson depends on `nixpkgs-lib` (not full nixpkgs). It consumes the library functions and re-exports them as part of its composed `lib` (via `mkLib`), so downstream projects get nixpkgs-lib functions plus caisson's extensions through the caisson dependency.

## Development Tools
- **Git:** Used for version control and managing the project's source code.
- **Nix Flakes:** The packaging format used for the project, enabling reproducible builds and dependency management.
- **nixfmt (RFC-style):** The official formatter, enforcing **Nix RFC 166** style rules.

## Integration
- The framework is consumed as a Nix flake input by downstream projects.
- It integrates deeply with the `flake-parts` module system to provide its structural features.