# SPDX-License-Identifier: MIT
#
# The option types the core module declares its options with. One
# definition, referenced by the core module and re-exported under
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

  # The manifest type: structural, checked on the export side only.
  # A producer validates the manifest it publishes in its CI;
  # consumers assume shape.
  manifest = lib.mkOptionType {
    name = "caissonManifest";
    description = "caisson-core lib manifest ({ inputs, modules, libOverlays, defaultEcosystemSrc, projects, systems })";
    descriptionClass = "noun";
    check =
      v:
      builtins.isAttrs v
      && builtins.isAttrs (v.inputs or null)
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
