# SPDX-License-Identifier: MIT
#
# The flake outputs of what the selectors chose. Of the exported
# modules, `flake.modules` holds those that
# `caisson.flakeOutputs.modules` selects. The exported lib overlays
# and package overlays are in the manifest, which is in the `lib`
# output. They are entries in the shape caisson registers, so they
# have no flake output. These
# flake-parts conventions are on top: the `flake` class always exports a
# `default` entry (an empty module unless the selection provides it),
# so `flakeModules.default` exists for consumers that import it by
# convention, and `flake.flakeModules` mirrors `flake.modules.flake`.
#
# The configurations declared beneath the flake, at any depth, are
# published as well, each under the output attribute set its
# integration declares (`flake.nixosConfigurations`), named from its
# path: a name that is alone stays bare, and names that collide gain
# the segments that tell them apart.
{ config, lib, ... }:
let
  exports = config.caisson.exports;

  # The exported modules that the flake also publishes in its `modules`
  # output.
  publishedModules = config.caisson.flakeOutputs.modules exports.modules;
in
{
  options.caisson.flakeOutputs.modules = lib.mkOption {
    type = lib.types.functionTo (lib.types.attrsOf (lib.types.attrsOf lib.types.deferredModule));
    default = modules: modules;
    defaultText = lib.literalExpression "modules: modules";
    example = lib.literalExpression ''
      modules: modules // { nixos = removeAttrs modules.nixos [ "needs-caisson" ]; }
    '';
    description = ''
      Function that selects which of the exported modules the flake
      also publishes in its `modules` flake output. It receives the
      exported modules, as an attribute set of classes that each hold
      modules by name, and returns the modules to publish in the same
      shape.

      The exported modules are the modules that the
      `caisson.modules.<class>.exported` selectors chose. They are in
      the manifest of the flake, and a flake that lists this flake in
      `projects` reads them from the manifest. That flake gets every
      exported module, whatever this function returns.

      The `modules` flake output is for a flake that imports a module
      of this flake by hand, as `inputs.<flake>.modules.<class>.<name>`.
      Leave a module out of the output when it only works inside an
      evaluation that caisson makes, because it reads the options under
      `caisson` or the library under `lib.caisson`.
    '';
  };

  config = {
    flake = lib.caisson.integrations.publish exports.configurations // {
      # The `lib` output is the composed library of this evaluation.
      #
      # The manifest of this evaluation is in the composed library,
      # at `lib.caisson-core.evalManifest`. A flake that lists this
      # flake in `projects` reads what this flake exports from that
      # manifest. The manifest is published in `lib` because the
      # other flake outputs each have a fixed shape.
      inherit lib;
      modules = publishedModules // {
        flake = {
          default = { };
        }
        // (publishedModules.flake or { });
      };
      flakeModules = config.flake.modules.flake;
    };
  };
}
