# SPDX-License-Identifier: MIT
#
# A hjem module with which a hjem configuration records what it
# applied, so that the configurations declared inside it can detect
# drift. It is the counterpart, for a hjem configuration, of the
# machine module `activation-marker`: see there for why.
#
# The module adds a file to the files of the configuration,
# `.local/state/caisson/markers/hjem-<name>.json` in the directory of
# the user, holding the identity of the childless evaluation of the
# configuration: its manifest file without the configurations declared
# inside it. hjem links the file into place when it applies the
# configuration.
#
# caisson's `default` hjem module imports this module. The file is
# added only when the configuration has a configuration declared inside
# it that checks it, and not in the childless evaluation.
{ ... }:
{
  config,
  lib,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  checked = builtins.any (selection.checksMarkerOf evalManifest) config.caisson.exports.configurations;

  marker = selection.markerOf evalManifest;
in
{
  config = lib.mkIf (!evalManifest.childless && checked && marker != null) {
    files.".local/state/caisson/markers/${selection.markerFileName evalManifest}".text = marker.text;
  };
}
