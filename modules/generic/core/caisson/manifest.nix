# SPDX-License-Identifier: MIT
{ lib, ... }:
let
  types = import ../types.nix { inherit lib; };
in
{
  options.caisson.manifest = lib.mkOption {
    type = types.manifest;
    readOnly = true;
    default =
      if lib.caisson-core.evalManifest != null then
        lib.caisson-core.evalManifest
      else
        lib.caisson-core.libManifest;
    defaultText = "the composed library's caisson-core.evalManifest, or its libManifest in an evaluation that carries none";
    description = ''
      The manifest of this evaluation, which carries the registries
      and declared facts of the composition it is declared under; in
      an evaluation that carries none, the composition's manifest.
      Of the composition: `sources` and `root` as the pin
      reader gave them to mkLib (each pin recorded against the root),
      `defaultEcosystemSrc`, `systems` and `projects` as given to mkLib,
      plus the registered
      `libOverlays` and `modules` dictionaries (project entries under
      `<project>/<name>`, locals winning). Checks live on the export
      side, which is here: reading this option type-checks the
      manifest, and `caisson.exports` is drawn from it. A producer
      validates the manifest it publishes in its CI; consumers assume
      shape.
    '';
  };
}
