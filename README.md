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

caisson exists to make a flake ecosystem practical to build on.

If you publish a flake, caisson lets you depend on whatever you need
without making that your consumer's problem. What you export has access
to your declared inputs, so a consumer does not have to re-declare your
dependencies or `follows`-pin them to make your modules work. They can
still override a pin when they want to.

If you consume one, adopting caisson yourself gives you the machinery to
compose what you pull in: libraries and modules from several flakes fit
together instead of colliding.

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

## Integrations

caisson ships integrations that carry its benefits throughout the Nix
ecosystem:

| Integration | for |
| --- | --- |
| `flake-parts` | flake outputs |
| `nixpkgs` | package sets and overlays |
| `nixos` | NixOS configurations |
| `home-manager` | Home Manager configurations |
| `terranix` | Terranix and Terraform configurations |
| `colmena` | Colmena deployment hives |
| `system-manager` | system-manager configurations on foreign distros |

The integrations work against the versions of these dependencies that you
already have. caisson pins none of them, and declares no flake inputs of
its own, so adding it does not put anything in your lock file to keep
aligned, and there is no chain of `follows` to enumerate downstream.

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
