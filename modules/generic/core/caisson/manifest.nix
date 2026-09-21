# SPDX-License-Identifier: MIT
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.manifest = lib.mkOption {
    type = types.manifest;
    readOnly = true;
    default = lib.caisson-core.libManifest;
    defaultText = "the composed library's caisson-core.libManifest";
    description = ''
      The composition's manifest: `inputs`, `defaultEcosystemSrc`,
      `systems` and `projects` as given to mkLib, plus the registered
      `libOverlays` and `modules` dictionaries (project entries under
      `<project>/<name>`, locals winning). Checks live on the export
      side, which is here: reading this option type-checks the
      manifest, and `caisson.exports` is drawn from it. A producer
      validates the manifest it publishes in its CI; consumers assume
      shape.
    '';
  };
}
