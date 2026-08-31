<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/wordmark-dark.svg">
    <img alt="caisson" src="assets/brand/wordmark.svg" width="480">
  </picture>
</p>

<p align="center"><em>The foundation framework for composable Nix flakes.</em></p>

---

A caisson is the watertight structure used to sink a bridge foundation to
bedrock. It is not scaffolding: once sealed, it *becomes* the foundation:
the part of the bridge no one sees, and the part everything else stands
on. caisson can provide that structure for a Nix flake: closed inputs, disciplined
library composition, and class-keyed modules, built on
[flake-parts](https://flake.parts).

## Philosophy

### Closed inputs

**The problem:** in a typical `flake-parts` setup, modules rely on utility
libraries or helper flakes being passed down from the top level. This
creates an unhygienic closure: a module implicitly assumes that the
*consumer's* flake has declared and forwarded every specialized dependency
it needs, forcing users to add another flake's internal dependencies to
their own `flake.nix`. A new internal dependency adds drag for
downstream users, which quietly discourages modularity.

**The solution:** caisson closes modules and library overlays over the
inputs *of the flake that defines them*. A module can rely on its
dependencies being satisfied without assuming anything about the
consumer's inputs, so internal dependencies stay internal, while the
standard flake mechanisms for overriding any input remain available to
consumers who need a specific version.

### Library overlays

**The status quo:** library composition is rare in the Nix ecosystem and
sometimes dismissed as an anti-pattern, a caution inherited from a
history of monkey-patching, where extensions overwrote global functions
and produced fragile dependency graphs.

**The thesis:** the community has overcorrected. The problem was never
composition; it was composition without discipline. Giving up on it costs
us doubly: shared abstractions become impossible at the library level, and
module authors compensate with ad-hoc, inconsistently named module
parameters to inject logic that should have been a `lib` reference.

**The solution:** caisson structures composition through namespacing.
A flake exports its logic under `lib.<namespace>` (by
convention, the flake's own name) instead of competing for the global
namespace, and library overlays declare their dependencies on each other
explicitly, composing in dependency order. Layered abstractions without
global pollution and without bloated module arguments.

### Module classes

Modules register under a class key naming the module system they belong
to: `flake` for flake-parts modules. The class keeps a module from
being imported into an evaluation that can't understand it, and the
shipped integrations register further classes for other module
ecosystems (NixOS, Home Manager, and friends).

## Integrations

caisson ships integrations that carry the same conventions into other
module ecosystems, each a library overlay contributing a
`lib.caisson.<ecosystem>` namespace and registering its own module class:
`nixpkgs` (package sets and overlays), `nixos`, `home-manager`,
`terranix` (Terranix/Terraform), `colmena` (deployment hives), and
`system-manager` (foreign distros). Each takes its ecosystem as
an explicit `ecosystemSrc` argument and pins nothing itself.

## Quick start

Use `caisson-core.mkLib` to compose your library, then `mkFlake` to
produce the flake outputs. By convention, your primary configuration
lives in `configs/flake-parts/<flake-name>`.

```nix
{
  inputs.caisson.url = "github:nix-caisson/caisson";

  outputs = inputs@{ self, caisson, ... }:
    let

      # Compose a library: the machinery lands under lib.caisson-core,
      # and caisson's flake-parts integration overlay contributes
      # lib.caisson (mkFlake and friends).
      lib = caisson.lib.caisson-core.mkLib {
        inherit inputs;

        # Register class-keyed modules. This function receives the composed lib.
        modules = lib: {
          flake = {
            # The flake-parts modules this flake defines: closed over your
            # inputs, importable here, exportable to downstream consumers.
            default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
            # other = lib.caisson.mkFlakeModule inputs.other-flake.flakeModules.default;
          };
        };

        # The library overlays this flake registers. This function receives
        # an input-closed mkLibOverlay helper; already-built overlays (like
        # caisson's integrations) register directly.
        libOverlays = mkLibOverlay: {
          flake-parts = caisson.libOverlays.flake-parts;
          default = mkLibOverlay ./lib-overlays/default;
          # other = inputs.other-flake.libOverlays.default;
        };

        # Select which of the registered overlays to apply to this flake's lib.
        libOverlayImports = overlays: builtins.attrValues { inherit (overlays) flake-parts default; };

      };

    in lib.caisson.mkFlake {

      # Convention: your primary config lives in configs/flake-parts/<flake-name>
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/my-flake;

      # Select which modules (yours or your dependencies') this flake composes.
      moduleImports = modules: { inherit (modules) default; };

    };
}
```

## Going deeper

- [`docs/concepts/`](docs/concepts/): closed inputs, module classes,
  library overlays, and the library lifecycle, each explained with the
  reasoning behind the design.
- [`docs/reference/`](docs/reference/): the `lib.caisson` API and module
  options.
- [`examples/literate-flake/`](examples/literate-flake/): a working,
  annotated flake demonstrating the whole structure end to end.

## Verification

```
nix flake check
```

runs the unit tests and integration flakes (consumer flakes that import
this project and assert that composition behaves as documented).

## Binary cache

CI publishes the store paths it builds to a public cache at
`caisson.cachix.org`, signed with the project's own key. Using it is
optional; everything builds from source without it.

```
cachix use caisson
```

or, directly in Nix configuration:

```
extra-substituters = https://caisson.cachix.org
extra-trusted-public-keys = caisson.cachix.org-1:iAqoNapIW5L9DR+bKG9JjAsGkfn7J2jez3sFgqFxwl0=
```

## Trademarks

Despite the org name, caisson is an independent project and is not affiliated with, endorsed
by, or sponsored by the NixOS Foundation. Nix and NixOS are trademarks
of the NixOS Foundation.
