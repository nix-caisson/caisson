# The composition calculus

The composition calculus is the foundation layer under caisson's
library composition. It is implemented in
[caisson-core](https://github.com/nix-caisson/caisson-core), a
zero-input flake whose library code references nothing but Nix
builtins, and it defines one small set of rules for turning a list of
overlay-shaped pieces into a composed library.

caisson's own `mkLib` composes on this engine: overlay chains are
flattened depth-first (imports before self, duplicates preserved) and
folded as anonymous entries over the base library, the sequence
described in [Library lifecycle](./library-lifecycle.md). caisson
also exports its contributions in keyed calculus form (see
[`entriesFor`](#caissons-entries) below) for consumers composing with
`caisson-core` directly.

## Entries

The unit of composition is an *entry*:

```nix
{
  key = "example.base";   # stable identity: a string, or null
  imports = [ ];          # entries this entry depends on
  overlay = final: prev: { greet = name: "hello, ${name}"; };
}
```

`compose { entries = [ ... ]; }` walks the entries and their imports,
applies their overlays as a classic overlay fold, and returns the
composed library together with composition metadata.

## The rules

**Imports are reachability.** Listing an entry pulls its transitive
imports into the composition. The walk is depth-first and post-order,
so an entry's imports precede it in application order.

**The key is identity.** A keyed entry applies once no matter how many
entries import it. The first occurrence of a key fixes its position;
the last occurrence supplies its value. Mentioning a key again
therefore *replaces* that entry wholesale, which is the calculus's
override mechanism: there are no priority annotations, and the answer
to "I need this entry to behave differently" is to replace the entry.

**Replacement inherits the replaced slot.** A replacement's own
imports join the composition, but at the walk's current end: they are
guaranteed to be present, not to precede the replacement. If you
replace an entry, you stand where it stood.

**Cycles terminate and mean nothing.** The walk skips a key already on
its own path. Members of an import cycle get no ordering guarantee
relative to each other; everything else is unaffected.

**Keyless entries are a local tail.** An entry with `key = null`
cannot be imported, applies after the entire keyed world in list
order, and stacks when listed repeatedly. Having no key, it can never
be replaced. This is the consumer's private patch layer.

**Application is a classic overlay fold.** `prev` is everything
accumulated so far; references through `final` see the finished
fixpoint. One law follows from the fixpoint: an overlay's output
attribute *names* must not depend on `final`.

## Polyfills

The rules make patching-over-a-dependency reliable. A polyfill
imports the entry it patches, which guarantees the target is in the
composition and already applied when the polyfill's overlay reads
`prev`:

```nix
polyfill = {
  key = "example.backport";
  imports = [ base ];
  overlay = final: prev: {
    concatLines = prev.concatLines or (lines: prev.concatStringsSep "\n" lines + "\n");
  };
};
```

The `prev.concatLines or ...` shape adds the function only where the
base does not already provide it, so the same entry composes correctly
over old and new bases.

## Ecosystem sources

The calculus deliberately fetches nothing. Sources for whole
ecosystems (a nixpkgs `lib` directory, a flake-parts tree) arrive as
explicit arguments, and `caisson-core` ships a layered resolver for
them: an explicit argument wins, then the client repository's declared
defaults, then an input with exactly the declared name. A full miss
resolves to `null` rather than an error; interpreting a miss belongs
to the caller.

## caisson's entries

caisson exports its own library as calculus entries through
`lib.composition.entriesFor`:

```nix
caisson.lib.composition.entriesFor {
  # a directory importable as nixpkgs' lib, e.g. "${nixpkgs}/lib"
  # or "${nixpkgs-lib}/lib" for the nixpkgs.lib mirror
  ecosystemSrc = "${inputs.nixpkgs-lib}/lib";
}
# => { base, caisson-lib,
#      flake-parts, tooling,
#      nixpkgs, nixos, home-manager,
#      colmena, terranix, system-manager }
```

`base` (key `caisson.nixpkgs-lib`) contributes the nixpkgs library
the composition builds on; `caisson-lib` (key `caisson.lib`) imports
it and contributes the `caisson-core` machinery namespace, the same
injection `mkLib` performs.

The remaining entries are caisson's integrations and tooling, each
importing `caisson-lib` and contributing its own namespace
(`caisson.mkFlake` from the flake-parts entry,
`caisson.nixos.mkSystem`, `caisson.home-manager.mkHomeConfiguration`,
and so on). An integration takes its target as an explicit
`ecosystemSrc` argument at its own entry points and pins nothing
itself; flake-parts is the exception, closing over caisson's own pin.
