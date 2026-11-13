# SPDX-License-Identifier: MIT
#
# The option types the core module declares its options with. The
# core module imports this file, and the integrations overlay
# publishes it as `lib.caisson-core.types`.
{ lib }:
let
  isLibOverlay =
    v:
    builtins.isAttrs v
    && builtins.hasAttr "overlay" v
    && builtins.isFunction v.overlay
    && builtins.isList (v.imports or [ ])
    && builtins.all isLibOverlay (v.imports or [ ]);

  isPkgOverlay = v: builtins.isAttrs v && builtins.isFunction (v.overlay or null);

  # An attribute set of registered entries, merged as one attribute set.
  # The definitions are joined with `//`, and an entry is checked when
  # it is read. Every configuration defines the exports of its library,
  # so merging each entry as a separate option would cost a merge per
  # entry in every configuration.
  #
  # An option of such a type can have more than one definition of the
  # same entry. A configuration and the configurations declared inside
  # it share one library. Each of them exports the entries of that
  # library, and a configuration also passes up what the configurations
  # inside it export. So the same entry reaches a configuration from two
  # places, and either definition is the entry.
  entries =
    {
      name,
      description,
      checkEntry,
    }:
    lib.mkOptionType {
      inherit name;
      description = "attribute set of ${description}";
      descriptionClass = "composite";
      check = builtins.isAttrs;
      merge =
        loc: defs:
        builtins.mapAttrs (
          entryName: entry:
          if checkEntry entry then
            entry
          else
            throw "The entry `${entryName}` of `${lib.showOption loc}` is not a ${description}."
        ) (builtins.foldl' (merged: def: merged // def.value) { } defs);
    };
in
{

  libOverlay = lib.mkOptionType {
    name = "libOverlay";
    description = "library overlay ({ imports ? [ ], overlay })";
    descriptionClass = "noun";
    check = isLibOverlay;
  };

  # A registered package overlay, as a configuration exports it.
  pkgOverlay = lib.mkOptionType {
    name = "pkgOverlay";
    description = "package overlay ({ imports ? [ ], overlay })";
    descriptionClass = "noun";
    check = isPkgOverlay;
  };

  # The registered library overlays and package overlays, by name, as a
  # configuration exports them.
  libOverlays = entries {
    name = "libOverlays";
    description = "library overlays ({ imports ? [ ], overlay })";
    checkEntry = isLibOverlay;
  };
  pkgOverlays = entries {
    name = "pkgOverlays";
    description = "package overlays ({ imports ? [ ], overlay })";
    checkEntry = isPkgOverlay;
  };

  # A check a configuration declares, an entry of `caisson.checks`. In
  # a NixOS configuration, `caisson.checks.toplevel.enable = false;`
  # turns off the default check `toplevel` of the nixos integration. An
  # entry that names no `derivation` annotates the check of the same
  # name that the configuration already has: a default check of its
  # integration, or, under `perSystem` in flake-parts, the entry of the
  # same name in `checks`. An entry with a `top` declares the checks of
  # a test caisson top under `<name>-`.
  check = lib.types.submodule {
    options = {
      derivation = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression ''pkgs.runCommand "smoke" { } "touch $out"'';
        description = ''
          The derivation that is the check, for the system of the
          evaluation result that declares it: the check passes when the
          derivation builds. Null for an entry that annotates a check the
          configuration already has, and for an entry with a `top`.
        '';
      };
      top = lib.mkOption {
        type = lib.types.nullOr (lib.types.addCheck lib.types.raw builtins.isAttrs);
        default = null;
        example = lib.literalExpression ''
          lib.caisson.callConsumerFlake {
            path = ../../../tests/integration/basic-composition;
            pool = { inherit (inputs) flake-parts nixpkgs; };
          }
        '';
        description = ''
          A test caisson top, as a flake that `lib.caisson.callConsumerFlake`
          evaluates from source returns it, or any value with a `checks`
          output. Each check of that output for the system of this
          evaluation result is a check here, named `<name>-<check>`, where
          `<name>` is the name of this entry. When the value is a caisson
          top, its `caisson.manifest.checkRecord` gives each check its
          category and its description, and the check record of the
          configuration that declares this entry keeps that record entry
          under `top`. The `category` and `description` of this entry,
          where they are given, apply to every check of the test caisson
          top, and a check that neither names falls in the category
          `build`. An entry with a `top` sets no `derivation`.
        '';
      };
      category = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "eval";
        description = ''
          The name of the category of the check, a category declared in
          `caisson.checkCategories`. A check that sets a `derivation` names
          its category. An annotation that leaves it null keeps the
          category of the check it annotates.
        '';
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "the jellyfin data migrates from the last confirmed release to the pinned release";
        description = "A sentence saying what the check checks.";
      };
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the check is a check of the configuration. A check with
          `enable = false` stays in the `checks` record of the manifest with
          the definition that turned it off, and it is not gathered.
        '';
      };
    };
  };

  # A category of checks, an entry of `caisson.checkCategories`.
  checkCategory = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "A sentence saying what the checks of the category check.";
      };
      volatile = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether the result of a check of the category depends on
          something outside the build, such as a network, a service or a
          piece of hardware.
        '';
      };
    };
  };

  # A stage, an entry of `caisson.checkStages`.
  checkStage = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "A sentence saying what the checks the stage selects establish.";
      };
      select = lib.mkOption {
        type = lib.types.functionTo lib.types.bool;
        example = lib.literalExpression ''entry: entry.category != "vm"'';
        description = ''
          The function that says whether the stage selects a check. It
          receives an entry of the `checkRecord` of the manifest of the caisson top and
          returns true for a check the stage selects.
        '';
      };
    };
  };

  # The manifest type: structural, checked on the export side only.
  # A producer validates the manifest it publishes in its CI;
  # consumers assume shape.
  manifest = lib.mkOptionType {
    name = "caissonManifest";
    description = "caisson-core lib manifest ({ dependencies, root, modules, libOverlays, defaultEcosystemSrc, projects, systems })";
    descriptionClass = "noun";
    check =
      v:
      builtins.isAttrs v
      && builtins.isAttrs (v.dependencies or null)
      && ((v.root or null) == null || (builtins.isAttrs v.root && v.root ? outPath))
      && builtins.isAttrs (v.defaultEcosystemSrc or { })
      && builtins.isAttrs (v.projects or { })
      && (
        (v.systems or null) == null
        || (builtins.isList v.systems && builtins.all builtins.isString v.systems)
      )
      && builtins.isAttrs (v.modules or null)
      && builtins.all builtins.isAttrs (builtins.attrValues v.modules)
      && builtins.isAttrs (v.configs or { })
      && builtins.all builtins.isAttrs (builtins.attrValues (v.configs or { }))
      && builtins.isAttrs (v.libOverlays or null);
  };

}
