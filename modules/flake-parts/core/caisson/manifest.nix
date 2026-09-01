# SPDX-License-Identifier: MIT
{ lib, ... }:
{
  options.caisson.manifest = lib.mkOption {
    type = lib.caisson.types.manifest;
    readOnly = true;
    default = lib.caisson-core.manifest;
    defaultText = "the composed library's caisson-core.manifest";
    description = ''
      The composition's manifest: `inputs`, `ecosystems`, and
      `projects` as given to mkLib, plus the registered `libOverlays`
      and `modules` dictionaries (project entries under
      `<project>/<name>`, locals winning). Checks live on the export
      side, which is here: reading this option type-checks the
      manifest, and the `flake.modules` and `flake.libOverlays`
      projections are drawn from it. Producers validate their own
      manifests in their own CI; consumers assume shape.
    '';
  };
}
