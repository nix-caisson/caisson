# SPDX-License-Identifier: MIT
#
# The configurations declared beneath this configuration: for each
# integration, `caisson.<integration>.configurations.<name>` takes what
# that integration's `mkConfiguration` returns and holds the finished
# manifest. A configuration learns its name and its parent from where
# it is declared, so the option finalizes each entry when it is read,
# with the attribute it is declared under and the childless manifest
# of this evaluation. The names are known without finalizing anything.
#
# Re-export: `caisson.<integration>.exported` selects, from those
# configurations, those this configuration passes up, and what each
# selected configuration exports is merged into `caisson.exports` here.
# It runs in the evaluation that holds the configurations and not in the
# childless view, where their results are not readable.
{ config, lib, ... }:
let

  manifest = lib.caisson-core.evalManifest;

  integrations = lib.caisson.integrations.names;

  isManifest = value: builtins.isAttrs value && (value._type or null) == "caisson-manifest";

  # What each integration's `exported` selected of the configurations
  # declared here, by integration and then name: nothing in the
  # childless view, and nothing in an evaluation that carries no
  # manifest.
  selected =
    if manifest == null || manifest.childless then
      { }
    else
      lib.genAttrs integrations (
        integration: config.caisson.${integration}.exported config.caisson.${integration}.configurations
      );

  # The manifests passed up: a configuration evaluated at a system
  # stands for each of its evaluations.
  exported = builtins.concatMap (
    integration:
    builtins.concatMap (
      finalized: if isManifest finalized then [ finalized ] else builtins.attrValues finalized
    ) (builtins.attrValues selected.${integration})
  ) (builtins.attrNames selected);

  # A registry part of `caisson.exports`, as the configurations passed
  # up export it. A configuration whose integration exports no
  # registries contributes nothing.
  passedUp =
    part:
    lib.mkMerge (
      builtins.map (child: child.outputs.exports.${part}) (
        builtins.filter (child: child.outputs ? exports) exported
      )
    );

  finalize =
    integration: name: child:
    let
      what = "`caisson.${integration}.configurations.${name}`";
      finalized = lib.caisson-core.finalizeChild {
        inherit name what;
        parent = manifest.childlessManifest;
      } child;
      # The integration of what was declared: of the manifest, or of
      # the evaluations of a configuration evaluated at a system, null
      # where it has none.
      declaredType =
        if isManifest finalized then
          finalized.type
        else if finalized == { } then
          null
        else
          (builtins.head (builtins.attrValues finalized)).type;
    in
    if manifest == null then
      throw ''
        ${what} is declared in an evaluation that carries no manifest
        (`lib.caisson-core.evalManifest` is null there), so no
        configuration can be finalized beneath it.
      ''
    else if manifest.childless then
      throw ''
        The result of the ${integration} configuration `${name}` is not
        readable from the ${manifest.type} configuration it is declared in, or
        from another configuration beneath that configuration; only the
        options of the ${manifest.type} configuration are readable there.
        Put the value in one of those options and read it there.
      ''
    else if declaredType != null && declaredType != integration then
      throw ''
        ${what} is declared with a ${declaredType} configuration.
        Declare it under `caisson.${declaredType}.configurations`.
      ''
    else
      finalized;

in
{
  config.caisson.exports = lib.genAttrs [ "lib" "libOverlays" "modules" "pkgOverlays" ] passedUp // {
    configurations = lib.caisson.integrations.entriesOf selected;
  };

  options.caisson = lib.genAttrs integrations (integration: {
    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
      default = configurations: configurations;
      defaultText = lib.literalMD "every configuration declared";
      description = ''
        Function that selects which of the ${integration} configurations
        declared beneath this configuration it passes up. Receives
        `caisson.${integration}.configurations` and returns the subset to
        export; `_: { }` exports none. What each selected configuration
        exports is merged into this configuration's `caisson.exports`.
      '';
    };
    configurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      apply = builtins.mapAttrs (finalize integration);
      description = ''
        The ${integration} configurations declared beneath this
        configuration, by name: each is what
        `lib.caisson.${integration}.mkConfiguration` returns, and reads
        back as its manifest, finalized with the name it is declared
        under and this configuration as its parent. A configuration
        beneath sees this configuration without the configurations declared
        beneath it, so a definition that reads one of them is guarded
        with `!lib.caisson-core.evalManifest.childless`.
      '';
    };
  });
}
