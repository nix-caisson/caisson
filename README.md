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

<p align="center">
  <a href="https://github.com/nix-caisson/caisson/actions/workflows/drift.yml"><img alt="drift" src="https://github.com/nix-caisson/caisson/actions/workflows/drift.yml/badge.svg?branch=main&event=schedule"></a>
</p>

<p align="center"><sub>The drift badge reports the daily run of the pinned-world suite against the current upstreams (nixpkgs, home-manager, colmena, disko, nix-darwin, hjem, terranix, system-manager); red means an upstream moved and broke an expectation caisson holds.</sub></p>

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

Use `lib.caisson.mkLib` to compose your library, then
`lib.caisson.flake-parts.mkTopConfiguration` to produce the flake outputs. By convention, your primary configuration
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

      # Compose a library. Everything a flake writes is under
      # lib.caisson: the names that compose and register (mkLib,
      # mkModules, the registries, the manifest) and one namespace
      # per integration (lib.caisson.flake-parts, lib.caisson.nixos).
      lib = caisson.lib.caisson.mkLib {
        # The flake pin reader: your inputs as the pinned sources the
        # composition closes over, and the root from `self`.
        inherit (caisson.lib.caisson.pins.flake inputs) sources root;

        # The project's name: the name of the configuration below,
        # which no parent declares, and the namespace this flake
        # contributes to the composed library.
        name = "my-flake";

        # Consume caisson as a project: its integrations and its
        # exported modules join the registries under `caisson/<name>`.
        projects = { inherit caisson; };

        # The class-keyed modules this flake defines, read from
        # modules/<class>/<name>/default.nix: closed over your pinned sources,
        # importable here, exportable to downstream consumers. A flake
        # with another layout writes the registration by hand
        # (`modules = lib: { flake.default = lib.caisson.flake-parts.mkModule ./some/path; }`).
        modules = lib: lib.caisson.mkModules ./modules;

        # The configurations, read from configs/<class>/<name>/default.nix.
        configs = lib: lib.caisson.mkModules ./configs;

        # The library overlays this flake registers, read from
        # lib-overlays/<name>/default.nix. An already-built overlay (another
        # flake's export) registers by hand, directly.
        libOverlays = lib: lib.caisson.mkLibOverlays ./lib-overlays;

      };

    in lib.caisson.flake-parts.mkTopConfiguration {

      # Your primary config is the configuration registered under the name declared
      # above, configs/flake/my-flake. Pass `configModule` to evaluate
      # another.

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
| `darwin` | `nix-darwin` | macOS machines, evaluated with nix-darwin and published as the `darwinConfigurations` that `darwin-rebuild` reads; they activate the home-manager configurations and hjem configurations declared inside them |
| `nixos-minimal` | `nixpkgs` | the `nixos` class under the minimal evaluator (no NixOS base modules); a second integration over the class `nixos` owns |
| `home-manager` | `home-manager` | Home Manager configurations |
| `home-manager-minimal` | `home-manager` | the `homeManager` class with Home Manager's necessary modules alone, the configuration importing what it uses from `modulesPath`; a second integration over the class `home-manager` owns |
| `hjem` | `hjem` | the files and packages of a user, as hjem manifests; activated by the NixOS, darwin or system-manager configuration they are declared inside, or applied with `hjem standalone` |
| `terranix` | `terranix` | Terraform configurations written as terranix modules, published as `terranixConfigurations` of the `config.tf.json` files Terraform reads |
| `caisson-colmena` | `colmena` | colmena configurations whose machines are NixOS configurations declared inside them, published as the hive colmena's command reads; the colmena integration we recommend for new configurations |
| `colmena` | `colmena` | a hive written for colmena, taken as it is, with each node a NixOS configuration; for porting an existing hive and the modules written for it |
| `caisson-disko` | `disko` | disk layouts, with the NixOS configurations installed onto each declared inside it; a machine gets the layout's file systems and no disko scripts; the disko integration we recommend for new configurations |
| `disko` | `disko` | a standalone disk layout, written as disko reads it and published as the `diskoConfigurations.<name>` that disko's command formats and mounts; a machine that carries its layout, as `disko-install` and disko's image builder expect, is a NixOS configuration that selects caisson's `disko` NixOS module |
| `caisson-facter` | none | the hardware of a machine, a nixos-facter report checked against the report versions caisson knows and extended with a project's options, with the NixOS configurations that run on it declared inside it; a machine gets the report through nixpkgs' `hardware.facter` |
| `facter` | none | a `facter.json` as nixos-facter writes it, with the NixOS configurations that run on it declared inside it; a machine gets it as `hardware.facter.reportPath` |
| `caisson-microvm` | `microvm` | microvm.nix guests declared inside the NixOS host that runs them, each guest a NixOS configuration declared inside it that sets its own `microvm.*` options and gets microvm.nix's guest module by default; the host selects caisson's `microvm-host` NixOS module, which defines microvm.nix's `microvm.vms.<guest>` from them; the microvm integration we recommend for new configurations |
| `microvm` | `microvm` | a microvm.nix guest written as microvm.nix reads it, a NixOS configuration that sets its `microvm.*` options itself, declared inside the NixOS host that runs it; for porting an existing guest |
| `caisson-nixops4-composite` | `nixops4` | a composite of a NixOps4 deployment, evaluated when NixOps4 deploys, with its members, composites and resources, declared beneath it; it declares providers and reads the outputs of its members; the composite declared under the name `nixops4` where no composite holds it is the root, published as the `nixops4` output the NixOps4 command reads; the NixOps4 integration we recommend for new configurations |
| `caisson-nixops4-resource` | `nixops4` | a resource of a NixOps4 deployment, evaluated when NixOps4 deploys, holding the caisson configurations it deploys; a NixOS configuration declared inside it is deployed over SSH as nixops4-nixos deploys one |
| `nixops4` | `nixops4` | the root modules of a NixOps4 deployment, written as NixOps4 users write them for `mkRoot`, each component evaluated by caisson and each nixops4-nixos machine a caisson NixOS configuration; the configuration named `nixops4` is published as the `nixops4` output; for porting an existing deployment |
| `treefmt` | `treefmt-nix` | the formatters of a tree, as treefmt-nix modules; the configuration named `formatter` is published as the `formatter.<system>` that `nix fmt` runs |
| `nvf` | `nvf` | a Neovim written as nvf modules, published as `nvfConfigurations.<system>.<name>`, in the shape `neovimConfiguration` returns, kept in a separate Nix profile that the machine, home-manager configuration or hjem configuration it is declared inside activates |
| `nixvim` | `nixvim` | a Neovim written as nixvim modules, published as `nixvimConfigurations.<system>.<name>`, kept in a profile as an nvf configuration is |
| `topology` | `nix-topology` | the diagram of the NixOS configurations declared inside it, as nix-topology renders it; the configuration named `topology` is published as `topology.<system>` |
| `kubenix` | `kubenix` | Kubernetes resources written as kubenix modules, published as `kubenixConfigurations.<system>.<name>`, the evaluation, whose `config.kubernetes.result` is the JSON `kubectl apply -f` reads |
| `nixidy` | `nixidy` | an Argo CD environment written as nixidy modules, evaluated with nixidy's `mkEnv` and published as the `nixidyEnvs.<system>.<name>` the nixidy CLI reads |
| `system-manager` | `system-manager` | the systems of machines running another Linux distribution, published as the `systemConfigs` that `system-manager switch` reads; they activate the home-manager configurations and hjem configurations declared inside them, and the profiles of the nvf and nixvim configurations declared inside them |
| `structural` | none | a configuration that only exports and holds configurations beneath it: the top of a repository whose point is what it exports, such as caisson itself, or a layer at any depth |

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
`caisson.cachix.org`, signed with the project's key. Using it is
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
