# Ecosystem sources

Integrations do not pin their ecosystems: `caisson.nixos` has no
nixpkgs pin, and `caisson.home-manager` has no home-manager pin. You
pass the ecosystem in, as an argument called the ecosystem source, and
the integration calls the evaluator inside that source. A single
caisson revision therefore works with any nixpkgs, home-manager, or
colmena revision, and two consumers of that same caisson revision can
pin different revisions of each ecosystem.

## What a source is

An ecosystem is a community library outside of caisson at the center
of a modular Nix abstraction framework: usually one built on NixOS
modules, but it can be anything (e.g. package sets, `lib`
ecosystems). The ecosystem source is that project's source tree or
flake, in whatever shape its evaluator expects. Each integration
documents the shape it takes; in practice:

- `caisson.nixos` takes a nixpkgs source tree (it evaluates
  `nixos/lib/eval-config.nix` from it).
- `caisson.home-manager` takes a home-manager source tree.
- `caisson.colmena`, `caisson.terranix`, and
  `caisson.system-manager` take their project's flake (they call
  `lib.makeHive`, `lib.terranixConfiguration`, and
  `lib.makeSystemConfig` on it).

## How does caisson get access to ecosystem sources?

A source comes from one of three places, in priority order:

1. **Explicit argument.** `ecosystemSrc = inputs.nixpkgs;` at the
   call site always wins.
2. **Declared once.** `ecosystems.nixpkgs = inputs.nixpkgs;` at
   `mkLib` declares the composition's default for that name; every
   adapter in the composition picks it up, and the per-call argument
   disappears from your code.
3. **Exact-name input.** As a final fallback, an input of the
   composing flake named exactly like the ecosystem (`nixpkgs`,
   `home-manager`, ...) is used. Handy for leaf flakes that declare
   the input anyway.

A full miss is an error at the adapter, naming all three places. A
composition built without `mkLib` carries no declarations, so only
the explicit argument works there.
