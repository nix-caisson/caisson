# SPDX-License-Identifier: MIT
#
# The configurations declared beneath this one: for each integration,
# `caisson.<integration>.configurations.<name>` takes what that
# integration's `mkConfiguration` returns and holds the finished
# manifest. A configuration learns its name and its parent from where
# it is declared, so the option finalizes each one when it is read,
# with the attribute it is declared under and the childless manifest
# of this evaluation. The names are known without finalizing anything.
{ lib, ... }:
let

  manifest = lib.caisson-core.evalManifest;

  finalize =
    integration: name: child:
    let
      what = "`caisson.${integration}.configurations.${name}`";
      finalized = lib.caisson-core.finalizeChild {
        inherit name what;
        parent = manifest.childlessManifest;
      } child;
    in
    if manifest == null then
      throw ''
        ${what} is declared in an evaluation that carries no manifest
        (`lib.caisson-core.evalManifest` is null there), so no
        configuration can be finalized beneath it. A flake-parts
        evaluation is one.
      ''
    else if manifest.childless then
      throw ''
        The result of the ${integration} configuration `${name}` is not
        readable from the ${manifest.type} configuration it is declared in, or
        from another configuration beneath that one; only the options of
        the ${manifest.type} configuration are readable there. Put the value in
        one of those options and read it there.
      ''
    else if finalized.type != integration then
      throw ''
        ${what} is declared with a ${finalized.type} configuration.
        Declare it under `caisson.${finalized.type}.configurations`.
      ''
    else
      finalized;

in
{
  options.caisson = lib.genAttrs lib.caisson.integrations.names (integration: {
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
        beneath sees this one without the configurations declared
        beneath it, so a definition that reads one of them is guarded
        with `!lib.caisson-core.evalManifest.childless`.
      '';
    };
  });
}
