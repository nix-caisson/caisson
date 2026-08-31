# Getting started

A step-by-step first flake: create it, add a library overlay, register
a module, use an integration, then consume your flake from a second
one. The finished shape of every step also exists as a working flake
under `examples/literate-flake/` in the repository, with commentary.

## 1. A minimal caisson flake

Create a directory with this `flake.nix`:

```nix
{
  description = "my first caisson flake";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.follows = "caisson/flake-parts";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.mkLib {
        inherit inputs;
      };
    in
    lib.caisson.mkFlake {
      name = "my-flake";
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/my-flake;
    };
}
```

`mkLib` composes a library: nixpkgs' lib, the framework's `caisson`
namespace, and (later) your own overlays. `mkFlake` then evaluates
flake-parts with that library and your config module.

The config module is the flake's own top-level configuration. Create
`configs/flake-parts/my-flake/default.nix`:

```nix
{ ... }:
{ pkgs, ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "my-flake";

  perSystem =
    { pkgs, ... }:
    {
      packages.default = pkgs.hello;
    };
}
```

Note the two argument lists: every registered file takes the closure
attrset (`{ closure-inputs, ... }`) first, then its ordinary module
arguments. That convention is the subject of
[Closed inputs](concepts/closed-inputs.md).

Check it:

```sh
nix flake check
nix build
```

## 2. Add a library overlay

An overlay contributes a namespace to the composed library. Create
`lib-overlays/default/default.nix`:

```nix
{ ... }:
{
  imports = [ ];
  overlay = final: prev: {
    my-flake = (prev.my-flake or { }) // {
      greet = name: "hello, ${name}";
    };
  };
}
```

Register it in `flake.nix` and export it, and turn on the lib export
in the config module:

```nix
      lib = caisson.lib.mkLib {
        inherit inputs;
        libOverlays = mkLibOverlay: {
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
```

```nix
  caisson = {
    configInfo.configName = "my-flake";
    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    lib.export.enabled = true;
  };
```

Now `lib.my-flake.greet` is available everywhere the composed library
flows: in the config module, in registered modules, and (with the
export enabled) to consumers as `flake.lib`. Use it in `perSystem`:

```nix
      packages.default = pkgs.writeText "greeting" (lib.my-flake.greet "Nix");
```

## 3. Register a module

Modules are class-keyed: `flake` modules feed flake-parts, and
integration classes (`nixos`, `homeManager`, ...) feed their module
systems. Register a flake-class module:

```nix
      lib = caisson.lib.mkLib {
        inherit inputs;
        modules = lib: {
          flake.default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
        };
        libOverlays = mkLibOverlay: {
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
```

`modules/flake-parts/default/default.nix`:

```nix
{ ... }:
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell { packages = [ pkgs.nixfmt ]; };
    };
}
```

`mkFlake` applies the selected flake-class modules alongside the
config module (`moduleImports` selects; the default is all of them).
[Module classes](concepts/module-classes.md) covers registration,
selection, and export.

## 4. Use an integration

Integrations bring the same conventions to other module ecosystems
and take their target as an explicit `ecosystemSrc`. A NixOS system,
in the config module's `perSystem` or at the top level:

```nix
  flake.nixosConfigurations.example = lib.caisson-nixos.mkSystem {
    ecosystemSrc = inputs.nixpkgs;
    pkgSets.pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    configModule =
      { ... }:
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.05";
      };
  };
```

The composed library only contains `caisson-nixos` if its overlay is
in the composition; register it from caisson's exports:

```nix
        libOverlays = mkLibOverlay: {
          default = mkLibOverlay ./lib-overlays/default;
          caisson-nixos = inputs.caisson.libOverlays.caisson-nixos;
        };
```

The [library reference](reference/lib.md) documents every
integration namespace.

## 5. Consume your flake from another flake

A consumer registers your exported overlay the same way:

```nix
{
  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    my-flake.url = "github:you/my-flake";
    flake-parts.follows = "caisson/flake-parts";
  };

  outputs =
    inputs@{ caisson, my-flake, ... }:
    let
      lib = caisson.lib.mkLib {
        inherit inputs;
        libOverlays = _mkLibOverlay: {
          my-flake = my-flake.libOverlays.default;
        };
      };
    in
    lib.caisson.mkFlake {
      name = "consumer";
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/consumer;
    };
}
```

The consumer's composed library now has `lib.my-flake.greet`, and the
overlay's `imports` chain guarantees anything your overlay depends on
composes with it. Exported modules travel the same way, through
`my-flake.modules.<class>.<name>`.

## Where next

- [Closed inputs](concepts/closed-inputs.md), the convention every
  registered file follows.
- [The composition calculus](concepts/composition-calculus.md), the
  engine underneath, and composing with `caisson-core` directly.
- [Testing](./testing.md), including `callConsumerFlake` for testing
  consumer flakes without a push/lock cycle.
- [FAQ](faq.md) for the questions this page tends to raise.
