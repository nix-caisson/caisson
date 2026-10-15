# SPDX-License-Identifier: MIT
#
# Re-export: for each integration whose configurations this
# configuration can hold beneath it (the module of each integration
# declares `caisson.<integration>.configurations`),
# `caisson.<integration>.exported` selects, from those configurations,
# those this configuration passes up, and what each selected
# configuration exports is merged into `caisson.exports` here. It runs
# in the evaluation that holds the configurations and not in the
# childless view, where their results are not readable.
{
  config,
  lib,
  options,
  ...
}:
let

  manifest = lib.caisson-core.evalManifest;

  integrations = lib.caisson.integrations.integrationsIn options;

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

in
{
  config.caisson.exports = lib.genAttrs [ "libOverlays" "modules" "pkgOverlays" ] passedUp // {
    configurations = lib.caisson.integrations.entriesOf selected;
  };
}
