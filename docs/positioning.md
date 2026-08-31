# Choosing a flake framework

Where caisson sits relative to plain flake-parts, flakelight, and
snowfall-lib, characterized from those projects' own documentation.
The honest summary first: all four produce working flakes, and the
differences are about which conventions you want enforced by
machinery rather than by discipline.

## Plain flake-parts

flake-parts is a minimal module system mirroring the flake schema:
it splits configuration into modules, handles `perSystem`, and
deliberately avoids broader opinions, positioning itself as "a single
module that other repositories can build upon" with an ecosystem of
independent compatible modules.

caisson is built on flake-parts and keeps all of it. What it adds is
a set of enforced conventions on top: closed inputs (every registered
file takes an explicit closure argument list instead of reaching for
inputs ambiently), namespaced library overlays with declared
dependencies composed on the caisson-core engine, class-keyed
module registration and export, integrations that take their target
ecosystems as explicit `ecosystemSrc` arguments, and measured
evaluation-cost gates. Use plain flake-parts when you want the module
system and your own conventions; use caisson when you want these
conventions machine-enforced, particularly across several flakes that
consume each other's libraries and modules.

## flakelight

flakelight is a module-driven framework emphasizing automation:
sensible defaults, automatic import of nix files from a directory,
and auto-generated outputs (packages, overlays, formatters), with the
stance that what can be done automatically, should be.

caisson leans the other way: registration is explicit, namespaces are
explicit, dependencies between overlays are declared, and nothing is
inferred from file layout. If you value minimal ceremony in a single
project, flakelight gets a working flake with fewer lines. If you
value being able to trace every attribute of a composed library to a
declared registration, especially across a fleet of interdependent
flakes, that explicitness is caisson's point.

## snowfall-lib

snowfall-lib generates systems, packages, modules, and shells from
directory-structure conventions: predictable filesystem hierarchies
in exchange for eliminated boilerplate, targeting multi-system NixOS
and nix-darwin setups. Its repository currently describes it as
seeking new maintainers.

The comparison is similar to flakelight but stronger: snowfall infers
the most from layout, caisson infers nothing from layout. caisson's
integrations also differ structurally from a generator: they are thin
adapters over each target's own evaluator, taking the target as an
explicit source argument and pinning nothing.

## What is caisson-specific

Independently of the convention trade-offs above, three things are
distinctive here rather than variations on a shared theme:

- **The composition engine** ([concepts](concepts/composition-engine.md)):
  library composition with identity, dedup, wholesale replacement,
  and reliable polyfills, implemented in a zero-dependency engine
  (caisson-core) that is usable without caisson.
- **Explicit ecosystem sources**: integrations pin none of their
  targets; the consumer hands every ecosystem in, so one caisson
  serves any nixpkgs, home-manager, or colmena revision the consumer
  chooses.
- **Evaluation-weight gates** ([guide](eval-weight.md)): framework
  overhead is measured and held to committed ceilings in CI rather
  than described.

## The relationship to flakes

Flakes do two jobs today: acquisition (fetching, pinning, integrity)
and composition (deciding which copy of each dependency an evaluation
actually uses, via the `follows` pin bucket). caisson separates the
two. Flakes keep acquisition. Composition moves to the evaluation
layer, where the engine gives it real semantics: deduplication is
key identity, override is wholesale replacement of a keyed entry,
local patches are the keyless tail, and ecosystems (nixpkgs,
home-manager, and the rest) are handed in once as explicit
`ecosystemSrc` arguments instead of being re-pinned and re-wired
through every level of an input graph.

Everything caisson adds travels through the flake schema's one
freeform slot, the `lib` output: composed libraries, the module
registry, and the manifest (the capture of what `mkLib` consumed) all
live there, and the remaining flake outputs (`modules.<class>`,
`libOverlays`, per-system products) are projections from it that keep
the standard schema's addresses. A flake built this way needs only a
small, regular subset of the flake schema; nothing about it requires
upstream changes to evaluate.
