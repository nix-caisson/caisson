<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://nix-caisson.github.io/assets/brand/wordmark-dark.svg">
    <img alt="caisson" src="https://nix-caisson.github.io/assets/brand/wordmark.svg" width="480">
  </picture>
</p>

<p align="center"><em>The foundation framework for composable Nix flakes.</em></p>

<p align="center">
  <strong><a href="https://nix-caisson.github.io/">Website</a></strong> ·
  <strong><a href="https://nix-caisson.github.io/docs/">Documentation</a></strong> ·
  <a href="https://nix-caisson.github.io/docs/getting-started.html">Getting started</a> ·
  <a href="https://nix-caisson.github.io/docs/reference/lib.html">Reference</a>
</p>

---

caisson exists to make a flake ecosystem practical to build on.

If you publish a flake, caisson lets you depend on whatever you need
without making that your consumer's problem. What you export has access
to your declared inputs, so a consumer does not have to re-declare your
dependencies or `follows`-pin them to make your modules work. They can
still override a pin when they want to.

If you consume a flake, adopting caisson yourself gives you the machinery
to compose what you pull in: libraries and modules from several flakes
fit together instead of colliding.

## Quick start

Use `caisson-core.mkLib` to compose your library, then
`lib.caisson.flake-parts.mkConfiguration` to produce the flake outputs. By convention, your primary configuration
lives in `configs/flake/<flake-name>`, and the registrations are read
from the directories: `modules/<class>/<name>`, `configs/<class>/<name>`
and `lib-overlays/<name>`.

```nix
{
  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    # The ecosystems this flake composes with, declared here and
    # found by name: nixpkgs (its lib is the nixpkgs-lib part of the
    # composed library) and flake-parts (the flake evaluation).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs@{ self, caisson, ... }:
    let

      # Compose a library: the machinery lands under lib.caisson-core,
      # and caisson's flake-parts integration overlay contributes
      # lib.caisson (one namespace per integration target).
      core = caisson.lib.caisson-core;

      lib = core.mkLib {
        inherit inputs;

        # Consume caisson as a project: its integrations and its
        # exported modules join the registries under `caisson/<name>`.
        projects = { inherit caisson; };

        # The class-keyed modules this flake defines, read from
        # modules/<class>/<name>/default.nix: closed over your inputs,
        # importable here, exportable to downstream consumers. A flake
        # with another layout writes the registration by hand
        # (`modules = lib: { flake.default = lib.caisson.flake-parts.mkModule ./some/path; }`).
        modules = core.mkModules ./modules;

        # The configurations, read from configs/<class>/<name>/default.nix.
        configs = core.mkModules ./configs;

        # The library overlays this flake registers, read from
        # lib-overlays/<name>/default.nix. An already-built overlay (another
        # flake's export) registers by hand, directly.
        libOverlays = core.mkLibOverlays ./lib-overlays;

      };

    in lib.caisson.flake-parts.mkConfiguration {

      # Convention: your primary config lives in configs/flake/<flake-name>
      configModule = lib.caisson-core.configs.flake.my-flake;

      # Which registered flake modules apply. Omitted, every entry named
      # `default` applies (this flake's `default` and `caisson/default`);
      # the `core` entries apply regardless.
      # moduleImports = modules: [ modules.default modules."caisson/default" ];

    };
}
```

## Integrations

caisson ships integrations that carry its benefits throughout the Nix
ecosystem. Each integration wraps one ecosystem, and one ecosystem may
be wrapped by several integrations: `nixos` and `nixpkgs` both wrap
nixpkgs. The ecosystem column is the name an integration resolves its
source by.

| Integration | Ecosystem | for |
| --- | --- | --- |
| `flake-parts` | `flake-parts` | flake outputs |
| `nixpkgs` | `nixpkgs` | package sets and overlays |
| `nixos` | `nixpkgs` | NixOS configurations |
| `nixos-minimal` | `nixpkgs` | the `nixos` class under the minimal evaluator (no NixOS base modules); a second integration over the class `nixos` owns |
| `home-manager` | `home-manager` | Home Manager configurations |
| `terranix` | `terranix` | Terranix and Terraform configurations |
| `colmena` | `colmena` | Colmena deployment hives |
| `system-manager` | `system-manager` | system-manager configurations on foreign distros |
| `structural` | none | a configuration that only exports: the top of a repository whose point is what it exports, such as caisson itself |

Each integration finds its ecosystem in this order: the `ecosystemSrc`
argument, then `defaultEcosystemSrc.<name>` in your `mkLib` call, then
the entry named exactly `<name>` in the `inputs` you passed to `mkLib`.
caisson pins none of these ecosystems. caisson's flake inputs are
caisson-core, nixpkgs-lib and flake-parts, used when caisson itself is
evaluated.

## Going deeper

- [Concepts](https://nix-caisson.github.io/docs/concepts/closed-inputs.html):
  closed inputs, module classes, library overlays, and ecosystem sources,
  each explained with the reasoning behind the design.
- [Reference](https://nix-caisson.github.io/docs/reference/lib.html):
  the `lib.caisson` API and module options.
- [Deep dives](https://nix-caisson.github.io/docs/deep-dives/how-lib-is-composed.html):
  how `lib` is composed and how inputs are closed over.
- [`examples/literate-flake/`](examples/literate-flake/): a working,
  annotated flake demonstrating the whole structure end to end.

The documentation is maintained in
[nix-caisson/nix-caisson.github.io](https://github.com/nix-caisson/nix-caisson.github.io)
and published as [the caisson docs](https://nix-caisson.github.io/docs/);
this repository carries only the contributor notes under
[`docs/development/`](docs/development/).

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
