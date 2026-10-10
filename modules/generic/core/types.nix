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
in
{

  libOverlay = lib.mkOptionType {
    name = "libOverlay";
    description = "library overlay ({ imports ? [ ], overlay })";
    descriptionClass = "noun";
    check = isLibOverlay;
  };

  # A registered package overlay, as a configuration exports it.
  #
  # An option of this type can have more than one definition of the
  # same entry. A configuration and the configurations declared inside
  # it share one library. Each of them exports the package overlays of
  # that library, and a configuration also passes up what the
  # configurations inside it export. So the same entry reaches a
  # configuration from two places.
  #
  # The type has no merge function of its own, so the module system
  # merges the definitions as attribute sets. The definitions are the
  # same entry, and the result is that entry. `libOverlay` above works
  # the same way. The type `raw` would refuse the second definition.
  pkgOverlay = lib.mkOptionType {
    name = "pkgOverlay";
    description = "package overlay ({ imports ? [ ], overlay })";
    descriptionClass = "noun";
    check = v: builtins.isAttrs v && builtins.isFunction (v.overlay or null);
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
      && builtins.isAttrs (v.libOverlays or null)
      && builtins.all isLibOverlay (builtins.attrValues v.libOverlays);
  };

}
