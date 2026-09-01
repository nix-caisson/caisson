<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/wordmark-dark.svg">
    <img alt="caisson" src="assets/brand/wordmark.svg" width="480">
  </picture>
</p>

<p align="center"><em>The foundation framework for composable Nix flakes.</em></p>

<p align="center">
  <strong><a href="https://nix-caisson.github.io/caisson/">Website</a></strong> ·
  <strong><a href="https://nix-caisson.github.io/caisson/docs/">Documentation</a></strong> ·
  <a href="https://nix-caisson.github.io/caisson/docs/getting-started.html">Getting started</a> ·
  <a href="https://nix-caisson.github.io/caisson/docs/reference/lib.html">Reference</a>
</p>

---

A caisson is sunk to bedrock, sealed, and becomes the foundation: the part
of the bridge no one sees, and the part everything else stands on. caisson
can provide that structure for a Nix flake, built on
[flake-parts](https://flake.parts):

- **Closed inputs.** Modules and library overlays close over the inputs of
  the flake that defines them, so internal dependencies stay internal and
  consumers are not asked to re-declare them.
- **Library overlays.** A flake exports its logic under `lib.<namespace>`
  rather than competing for the global namespace, and overlays declare
  their dependencies on each other and compose in dependency order.
- **Module classes.** Modules register under a class key naming the module
  system they belong to, which keeps a module from being imported into an
  evaluation that cannot understand it.

The reasoning behind each, with examples, is on
[the website](https://nix-caisson.github.io/caisson/) and in
[the documentation](https://nix-caisson.github.io/caisson/docs/).

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

- [Concepts](https://nix-caisson.github.io/caisson/docs/concepts/closed-inputs.html):
  closed inputs, module classes, library overlays, and ecosystem sources,
  each explained with the reasoning behind the design.
- [Reference](https://nix-caisson.github.io/caisson/docs/reference/lib.html):
  the `lib.caisson` API and module options.
- [Deep dives](https://nix-caisson.github.io/caisson/docs/deep-dives/how-lib-is-composed.html):
  how `lib` is composed and how inputs are closed over.
- [`examples/literate-flake/`](examples/literate-flake/): a working,
  annotated flake demonstrating the whole structure end to end.

The documentation in this repository lives under [`docs/`](docs/) and is
published as [the caisson docs](https://nix-caisson.github.io/caisson/docs/).

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

Despite the org name, caisson is an independent project and is not
affiliated with, endorsed by, or sponsored by the NixOS Foundation.
Nix and NixOS are trademarks of the NixOS Foundation.
