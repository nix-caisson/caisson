# Overview

This is the documentation for the framework's design and API.

New here? [Getting started](getting-started.md) walks through a first
flake step by step; [Choosing a flake framework](positioning.md)
places caisson relative to plain flake-parts, flakelight, and
snowfall-lib; the [FAQ](faq.md) answers the questions the concept
pages tend to raise.

**Reference** documents the exported surface — the
[Library](reference/lib.md) functions and the
[Options](reference/options.md).

**Conventions** — [Repository layout](layout.md) describes the
directory conventions the documentation and examples assume.

**Concepts** explain the machinery and the reasoning behind it, in
reading order:

- [Closed inputs](concepts/closed-inputs.md) — how modules and library
  overlays close over the defining flake's inputs, and the explicit
  closure convention every registered thing follows.
- [Module classes](concepts/module-classes.md) — class-keyed module
  registration and export.
- [Library overlays](concepts/library-overlays.md) — namespaced,
  dependency-declaring `lib` composition, and the patterns for writing
  overlays.
- [Library lifecycle](concepts/library-lifecycle.md), the mechanics:
  how `mkLib` registers, selects, and composes the final `lib`.
- [The composition engine](concepts/composition-engine.md): the
  foundation contract under library composition, implemented in
  caisson-core, and caisson's entries onto it.

**Guides** — [Testing](./testing.md) covers unit and integration testing
(including `callConsumerFlake`), and
[Evaluation weight](eval-weight.md) covers measuring and gating
evaluation cost.

For a complete working flake with commentary, see
`examples/literate-flake/` in the repository. The repository README
covers the philosophy and the quick start.

---

caisson is an independent project and is not affiliated with, endorsed
by, or sponsored by the NixOS Foundation. Nix and NixOS are trademarks
of the NixOS Foundation.
