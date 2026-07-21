# caisson Development Commands

All commands should be run from the caisson project root.

## Initializing Environment

Nix manages dependencies automatically. To ensure all tools (like nix-unit) are available:
```bash
nix develop
```

## Core Verification

```bash
# Run all checks (unit tests, formatting, linting)
nix flake check

# Build specific output
nix build .#<output>
```

## Focused Testing

```bash
# Run a specific check (which may use nix-unit internally)
nix build .#checks.<system>.<checkName>

# With real-time log output
nix build .#checks.<system>.<checkName> -L
```

## Debugging Evaluation (Non-Interactive / Agent)

```bash
# Evaluate a specific attribute
nix eval .#lib.myFunction

# Evaluate an arbitrary expression using the flake
nix eval --expr '(builtins.getFlake (toString ./.)).lib.myFunction "input"'
```

## Debugging Evaluation in REPL (Interactive / Human)

```bash
nix repl .
# Inside REPL:
# :p lib.myNewFunction "input"
# :p flakeModules.default
```

## Input Management

```bash
# Re-lock after modifying flake.nix inputs
nix flake lock

# Update all inputs to latest
nix flake update

# Update a single input
nix flake update <name>
```

## Code Formatting

```bash
nix fmt
```

## Debugging Tips

- **Trace:** Use `--show-trace` with any `nix` command to see the full error stack.
- **Printf:** Use `builtins.trace "Label: ${value}" value` in Nix code to print values during evaluation.
