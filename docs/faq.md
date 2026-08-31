# FAQ

### What goes wrong without caisson that this fixes?

Three failure patterns from multi-flake setups. First, input
re-declaration: a flake-parts module that reaches for `inputs.foo`
works only if every downstream flake also declares `foo` and wires
its `follows` chain, so each level of consumption re-plumbs the
levels below it. Second, duplicate module identity: a module
consumed from two revisions of the same upstream (directly and
through a sibling whose lock is one bump behind) is two copies to
the module system and fails with "option ... is already declared".
Third, library collisions: overlays that write top-level attributes
fight over one namespace, and which definition wins depends on
registration order that no single flake controls. Closed inputs,
rev-independent module identity, namespaced overlays with declared
dependencies, and class-keyed registration are the corresponding
fixes. [Choosing a flake framework](positioning.md) covers the
trade-offs against the alternatives.

### What is `closure-inputs`, and who sets it?

A caisson convention, not a flake-parts primitive. When a file is
registered through `mkLibOverlay` or `mkModule`, the registering
flake's `inputs` are applied to it as the first argument list, under
the name `closure-inputs`. The value is always the inputs of the
flake that registered the file, so an exported overlay or module
keeps working in a consumer that never heard of its dependencies.
[Closed inputs](concepts/closed-inputs.md) is the full convention.

### What happens when two overlays define the same thing?

Composition is an ordered overlay fold: within one attribute, the
later overlay's definition wins, and `prev` gives it the earlier
one to build on. Two conventions keep this from being a fight:
every project writes its own namespace (`lib.my-flake.*`), so
cross-project collisions are structural rather than accidental, and
an overlay declares its dependencies as `imports`, so "later" is
determined by the declared graph rather than by registration
accident. The engine underneath also gives keyed entries identity,
which is what makes deliberate replacement and deduplication work;
[the composition engine](concepts/composition-engine.md) has the
exact rules.

### Can I adopt this incrementally in an existing flake-parts flake?

Yes. `mkFlake` wraps flake-parts' own `mkFlake`, and plain
flake-parts modules are registered or imported unchanged (files are
only wrapped when you pass them through `mkModule`, and a module
that takes the closure argument list can ignore it). A minimal
adoption is composing your library with `caisson-core.mkLib` and
handing your existing top-level module to `mkFlake` as the config
module; the conventions can then spread file by file.

### What does `mkFlakeModule` do to my module?

A thin normalization: it applies the closure argument list, records
the file's path as `_file`, and gives path-registered modules a
deduplication `key`. Evaluation stays flake-parts and the module
system; when something breaks you get the ordinary module-system
error, pointing at your file.

### Do I pin nixpkgs, home-manager, and the rest myself?

Yes, in your own flake, which is the point: an integration is glue
over the target's own evaluator, composing whatever source you hand
it, so caisson imposes no transitive pins and two consumers of the
same caisson can run different nixpkgs revisions. Version skew
between your ecosystems lives in your own lock, where you can see
and manage it. A flake that uses one source everywhere declares it
once at `mkLib` (`ecosystems.nixpkgs = inputs.nixpkgs;`) instead of
passing it at each call; an explicit argument always wins, and an
input named exactly like the ecosystem is the final fallback.

### Are all seven integrations equally real?

They are all thin adapters over their target's own evaluator, a few
hundred lines each, and every one is exercised end to end by the
pinned-world suite in caisson-compat on every change. flake-parts is
the deepest integration because caisson's own flake evaluation runs
through it; the others wrap `eval-config.nix`, home-manager's
evaluator, `makeHive`, `terranixConfiguration`, and
`makeSystemConfig` respectively.

### Is this vocabulary standard flake-parts, or invented here?

Module classes build on flake-parts' generic `flake.modules`
support, including its `_class` stamping; caisson adds the
registration, closure, and export machinery around it. Closed
inputs, library overlay composition, and the engine are caisson's
own. [Choosing a flake framework](positioning.md) maps the overlap
with other approaches.

### What does this cost at evaluation time?

A measured, gated amount. The eval-weight harness runs in CI and
holds the framework's own overhead (a minimal caisson consumer minus
a raw flake-parts flake) to committed ceilings on deterministic
counters: thunks, values, allocations, and full nixpkgs, nixpkgs-lib,
and module-system evaluation counts. The overhead is orders of
magnitude below a single nixpkgs evaluation.
[Evaluation weight](eval-weight.md) documents the harness and the
current numbers.

### How mature is this?

Pre-release. It was built as the foundation of the author's own
machine fleet, where every host, builder, and installer image runs
through it, and it is published for reuse; the contract described in
the docs is intended to freeze at the first release, and `main` is
rolling until then. There is no version number yet, and the
[caisson-compat](https://github.com/nix-caisson/caisson-compat)
repository is where the moving ecosystem is tracked against it.
