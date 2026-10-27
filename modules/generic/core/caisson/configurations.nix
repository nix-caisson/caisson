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

  # The integrations whose configurations a module of this evaluation
  # declares. An integration with none declared passes nothing up,
  # whatever its `exported` selects, so it is not read.
  integrations = lib.caisson.integrations.integrationsDeclaringIn options;

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

  # The manifests passed up: a configuration evaluated per system
  # stands for each of its evaluations. The entry of a deferred
  # configuration is no manifest and exports no registries.
  exported = builtins.concatMap (
    integration:
    builtins.concatMap (
      finalized:
      if isManifest finalized then
        [ finalized ]
      else if lib.caisson-core.isDeferred finalized then
        [ ]
      else
        builtins.attrValues finalized
    ) (builtins.attrValues selected.${integration})
  ) (builtins.attrNames selected);

  # What this configuration adds to the export record of what it
  # passes up, by integration: its `exportNote`, and the files that
  # define its `exported`. The module system records the file of each
  # definition of an option but not its line number, so a position
  # here has the file and a `line` of null. The module
  # system counts the default of an option among its definitions, at
  # the priority of `mkOptionDefault`, with the file that declares the
  # option, so a selector left at its default has no position.
  defaultPriority = (lib.mkOptionDefault null).priority;
  levels = lib.genAttrs integrations (
    integration:
    let
      exported = options.caisson.${integration}.exported;
    in
    {
      notes = lib.optional (
        config.caisson.${integration}.exportNote != null
      ) config.caisson.${integration}.exportNote;
      code =
        if exported.highestPrio >= defaultPriority then
          [ ]
        else
          builtins.map (definition: {
            inherit (definition) file;
            line = null;
          }) exported.definitionsWithLocations;
    }
  );

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
    configurations = lib.caisson.integrations.entriesOf levels selected;
  };
}
