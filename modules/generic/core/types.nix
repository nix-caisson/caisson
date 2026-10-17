# SPDX-License-Identifier: MIT
#
# The option types the core module declares its options with. The
# definition is referenced by the core module and re-exported under
# `lib.caisson.flake-parts.types` for the readers of that name.
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
  # it is read. Every evaluation defines the exports of its library, so
  # merging each entry as an option of its own would cost a merge per
  # entry in every evaluation.
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

  # The manifest type: structural, checked on the export side only.
  # A producer validates the manifest it publishes in its CI;
  # consumers assume shape.
  manifest = lib.mkOptionType {
    name = "caissonManifest";
    description = "caisson-core lib manifest ({ sources, root, modules, libOverlays, defaultEcosystemSrc, projects, systems })";
    descriptionClass = "noun";
    check =
      v:
      builtins.isAttrs v
      && builtins.isAttrs (v.sources or null)
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
