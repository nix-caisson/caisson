# SPDX-License-Identifier: MIT
#
# The package overlay registry's export selector: what of the entries
# registered through mkLib's `pkgOverlays` leaves the project. The
# selected entries are published as they are registered, keys and
# imports included, which is what a consumer's `projects` merge reads.
{ config, lib, ... }:
{
  options.caisson.pkgOverlays = {

    export.enabled = lib.mkEnableOption "package overlay registry export";

    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.attrsOf lib.types.raw);
      description = ''
        Function that selects which registered package overlays to
        export. Receives the package overlay registry (mkLib's
        `pkgOverlays`, with consumed projects' entries under
        `<project>/<name>`) and returns the subset to publish. Defaults
        to the entries this composition registers itself; an entry a
        consumed project contributed leaves only when a selector names
        it.
      '';
    };

  };

  config = {
    caisson.pkgOverlays = {
      export.enabled = lib.mkDefault true;
      exported = lib.mkDefault (lib.filterAttrs (_: entry: (entry.project or null) == null));
    };

    caisson.exports.pkgOverlays =
      if config.caisson.pkgOverlays.export.enabled then
        config.caisson.pkgOverlays.exported (config.caisson.manifest.pkgOverlays or { })
      else
        { };
  };
}
