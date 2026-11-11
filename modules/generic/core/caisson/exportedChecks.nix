# SPDX-License-Identifier: MIT
#
# The checks a top publishes: the checks gathered at and inside the
# configuration, `outputs.checks` of its manifest, as
# `caisson.exportedChecks` selects them. A structural top returns
# them as its `checks`, and the flake-parts integration publishes them
# as the flake's `checks` output.
{ config, lib, ... }:
let
  manifest = lib.caisson-core.evalManifest;
in
{
  options.caisson.exportedChecks = lib.mkOption {
    type = lib.types.functionTo (lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw));
    default = checks: checks;
    defaultText = lib.literalExpression "checks: checks";
    example = lib.literalExpression ''
      checks: builtins.mapAttrs (_: lib.filterAttrs (name: _: name != "lab-1-toplevel")) checks
    '';
    description = ''
      Function that selects which of the gathered checks this
      configuration publishes in its `checks` output. It receives the
      gathered checks, by system and then name, and returns the checks
      to publish in the same shape. A check left out of the output is
      still a check: the check record lists it, and the manifest holds
      it under `outputs.checks`.
    '';
  };

  config.caisson.exports.checks =
    if manifest == null then { } else config.caisson.exportedChecks (manifest.outputs.checks or { });
}
