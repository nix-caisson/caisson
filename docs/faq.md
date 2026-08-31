# FAQ

**Why closure attrsets instead of detecting what a file wants?**
Registered files take the closure attrset (`{ closure-inputs,
mkLibOverlay, ... }`) as an explicit first argument list in every case.
Shape or arity detection would make the contract depend on how a file
happens to be written; the fixed extra argument list makes it visible
in the file and identical everywhere. There is no detection: a
registered file that skips the closure argument list is an error.

**Why are library overlays namespaced?**
An overlay contributes to its own namespace (`lib.my-flake.*`) rather
than writing top-level attributes, so independently developed
overlays compose without colliding and the definition of any function
is findable from its namespace. The conventions are in
[Library overlays](concepts/library-overlays.md).

**Why do overlays declare `imports` instead of relying on
registration order?**
Order is a property of a particular composition; `imports` is a
property of the overlay. Declaring dependencies makes an exported
overlay self-contained: a consumer registers one value and its whole
chain composes with it, in the right order, without the consumer
knowing the chain exists.

**Why do integrations take `ecosystemSrc` instead of pinning their
targets?**
So the consumer controls every ecosystem version and caisson imposes
no transitive pins. An integration is glue: `caisson.nixos` composes
whatever nixpkgs you hand it, and two consumers of the same caisson
can run different nixpkgs revisions. The argument is explicit rather
than resolved from input names by convention.

**What exactly does `key = null` mean in an engine entry?**
No identity: the entry can never be deduplicated, replaced, or
imported by another entry, and it applies in list order. Keyed
entries are the shareable units; keyless entries are a consumer's
local patch layer. See
[the composition engine](concepts/composition-engine.md).

**Does overriding a nixpkgs lib function affect nixpkgs' own uses of
it?**
No. The base library is contributed to the composition as an opaque
attribute set, so an override changes what readers of the *composed*
library see, and the base's internal references keep their original
meanings. If you need a function patched for everything downstream of
the base, patch the base source you pass in.

**What may consumers rely on across caisson updates?**
Exported overlays and modules are plain flake outputs, consumable
without the framework. `main` is rolling; the eval-weight harness
gates composition cost, and the pinned-world suite in caisson-compat
tracks the moving ecosystem. Consumers who want current upstream
pins with standard `follows` control depend on caisson-compat.

**Why MIT?**
The framework is evaluation-time code in an MIT ecosystem (nixpkgs,
flake-parts, home-manager); matching removes license-compatibility
questions from every consumer decision.
