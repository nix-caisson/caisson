# Ecosystem sources

Integrations do not pin their targets. `caisson.nixos` does not carry
a nixpkgs; `caisson.home-manager` does not carry a home-manager. The
target arrives as a value, called the ecosystem source, and the
integration is glue over that target's own evaluator. This is what
lets one caisson serve any nixpkgs, home-manager, or colmena revision
the consumer chooses, and lets two consumers of the same caisson run
different revisions of everything.

## What a source is

Each integration documents the shape it expects; in practice:

- `caisson.nixos` takes a nixpkgs source tree (it evaluates
  `nixos/lib/eval-config.nix` from it).
- `caisson.home-manager` takes a home-manager source tree.
- `caisson.colmena`, `caisson.terranix`, and
  `caisson.system-manager` take their project's flake (they call
  `lib.makeHive`, `lib.terranixConfiguration`, and
  `lib.makeSystemConfig` on it).

## The three channels

A source reaches an adapter through one of three channels, in
priority order:

1. **Explicit argument.** `ecosystemSrc = inputs.nixpkgs;` at the
   call site always wins.
2. **Declared once.** `ecosystems.nixpkgs = inputs.nixpkgs;` at
   `mkLib` declares the composition's default for that name; every
   adapter in the composition picks it up, and the per-call argument
   disappears from your code.
3. **Exact-name input.** As a final fallback, an input of the
   composing flake named exactly like the ecosystem (`nixpkgs`,
   `home-manager`, ...) serves. Handy for leaf flakes that declare
   the input anyway.

A full miss is an error at the adapter, naming all three channels. A
composition built without `mkLib` carries no declarations, so only
the explicit channel exists there.

## What this means for your flake

You pin the ecosystems, in your own lock, which is the design: the
versions of nixpkgs and its peers are visible where you manage
everything else, version skew between them is a fact of your lock
rather than of something transitive, and updating an ecosystem is
`nix flake update`, not a framework release.
