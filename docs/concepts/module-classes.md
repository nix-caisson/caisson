# Module Classes

## Overview

caisson models modules as class-keyed sets. A class is a string key used to group related modules and control where they are exported in flake outputs.

- Registered modules live under `modules.<class>.<name>`
- Exported modules are published under `flake.modules.<class>.<name>`

This builds on flake-parts' generic `flake.modules` support while adding closed-inputs module normalization.

## mkModule Factory

`lib.caisson.mkModule` is class-parameterized:

```nix
mkModule = class: freeformModule: ...
```

Example:

```nix
modules = {
  flake = {
    default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
  };

  generic = {
    helper = lib.caisson.mkModule "generic" ./modules/generic/helper;
  };
};
```

The returned class-specific normalizer applies the closure attrset
(`{ closure-inputs, closure-lib, mkModule, ... }`) as the module's first
arg list. The `mkModule` closure member is bound to the same class, so
nested use of `mkModule` stays in that class.

## Registration APIs

`mkLib` registers modules through a single class-keyed hook:

- `modules`: a function `lib: { ... }` receiving the composed `lib`
  (whose helpers, like `lib.caisson.mkFlakeModule`, build the entries)
  and returning the class-keyed registration

Use `modules.flake` for flake-parts modules and other class keys for other module ecosystems. The shipped integrations (`caisson.nixos`, `caisson.home-manager`, `caisson.terranix`, `caisson.colmena`, `caisson.system-manager`, and `caisson.nixpkgs`) each register their own class this way; see the [library reference](../reference/lib.md).

## Consuming Exported Modules

A downstream flake can import modules published under any class via the upstream flake's `modules` output:

```nix
# In a downstream NixOS configuration:
imports = [ inputs.my-upstream.modules.nixos.myModule ];

# In a downstream home-manager configuration:
imports = [ inputs.my-upstream.modules.homeManager.myModule ];
```

The exported modules have their inputs already closed over, so importing one is possible without threading the upstream's dependencies.

## Export Controls

Per-class export controls live under:

- `caisson.modules.<class>.export.enabled`
- `caisson.modules.<class>.exported`

For flake-parts compatibility, `flake.flakeModules` mirrors
`flake.modules.flake`, and the `flake` class always exports a `default`
entry — an empty module unless the selection provides one — so
`flakeModules.default` exists for consumers that import it by
convention.

## Relationship to flake-parts

The `flake.modules` output is provided by flake-parts' `modules` extra module. When caisson wires exported modules into `flake.modules.<class>.<name>`, flake-parts stamps each module with `_class` and `_file` metadata. This means exported modules carry their class identity and source location, which module systems can use for diagnostics and class-checking (e.g., preventing a `nixos` module from being accidentally imported into a `homeManager` evaluation).
