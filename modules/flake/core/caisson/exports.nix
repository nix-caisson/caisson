# SPDX-License-Identifier: MIT
#
# The flake outputs of what the selectors chose. Of the exported
# modules, `flake.modules` holds those that
# `caisson.flakeOutputs.modules` selects. The exported lib overlays
# and package overlays are in the manifest, which is in the `lib`
# output, as entries in the shape caisson registers. These
# flake-parts conventions are on top: the `flake` class always exports a
# `default` entry (an empty module unless the selection provides it),
# so `flakeModules.default` exists for consumers that import it by
# convention, and `flake.flakeModules` is the same as `flake.modules.flake`.
#
# The configurations declared inside the flake and passed up to it,
# nested configurations included, are published as well, each under the
# output attribute set its
# integration declares (`flake.nixosConfigurations`), named from its
# path: a name that is alone stays bare, and names that collide gain
# the segments that tell them apart.
#
# The `checks` output holds the checks the flake gathers, as
# `caisson.exportedChecks` selects them: the checks of the flake under
# `perSystem`, and the checks of the configurations declared inside
# the flake. Beside them are the checks those configurations publish
# under `checks` through their `exportsTo`. They replace the entries
# flake-parts copies from `perSystem`, at a priority below
# `lib.mkForce`.
#
# A flake can hand its `checks` output to a partition, with the option
# `partitionedAttrs.checks` of flake-parts. flake-parts then evaluates
# the modules of the flake again for the partition, these modules
# among them, and publishes the `checks` of that evaluation with
# `lib.mkForce`. In a flake that does, the gathered checks stay out of
# the `checks` output, and the checks published through `exportsTo` are
# defined at the default priority, beside the entries flake-parts
# copies from `perSystem`.
{
  config,
  lib,
  options,
  ...
}:
let
  exports = config.caisson.exports;

  # The exported modules that the flake also publishes in its `modules`
  # output.
  publishedModules = config.caisson.flakeOutputs.modules exports.modules;

  # The configurations declared inside the flake, published under the
  # output attribute set of each.
  published = lib.caisson.integrations.publish exports.configurations;

  partitioned = options ? partitionedAttrs && config.partitionedAttrs ? checks;
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
      Function that selects which exported modules are also published
      in the `modules` output. It receives the exported modules, as an
      attribute set of classes that each hold modules by name, and
      returns the modules to publish in the same shape.

      The exported modules are the modules that the
      `caisson.modules.<class>.exported` selectors chose. They are in
      the manifest, and `mkLib` reads them from there for each entry
      of `projects`. `mkLib` reads every exported module, whatever
      this function returns.

      The `modules` output is for an import by hand, as
      `inputs.<input>.modules.<class>.<name>`.
      Leave a module out of the output when it only works inside an
      evaluation that caisson makes, because it reads the options under
      `caisson` or the library under `lib.caisson`.
    '';
  };

  config = {
    flake = builtins.removeAttrs published [ "checks" ] // {
      # The manifest of the flake, for the tools that read a caisson top
      # (`topside --flake`), with the export record of what the flake
      # publishes, keyed as the outputs are, and the check record of
      # the checks it gathers, keyed as `outputs.checks` of the
      # manifest is.
      caisson.manifest = lib.caisson-core.evalManifest // {
        exportRecord = lib.caisson.integrations.recordOf exports.configurations;
        checkRecord = lib.caisson.integrations.checkRecordOf lib.caisson-core.evalManifest;
      };
      checks =
        if partitioned then
          published.checks or { }
        else
          lib.mkOverride 60 (
            lib.caisson.integrations.checksOutputOf {
              gathered = exports.checks;
              published = published.checks or { };
            }
          );
      # The `lib` output is the composed library of this configuration.
      #
      # The manifest of this configuration is in the composed library,
      # at `lib.caisson-core.evalManifest`. `mkLib` reads the exports
      # from that manifest for each entry of `projects`. The manifest
      # is published in `lib` because the other outputs each have a
      # fixed shape.
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
