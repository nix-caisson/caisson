# SPDX-License-Identifier: MIT
#
# A home-manager module with which a home records what it applied, so
# that the configurations declared inside it can detect drift. It is the
# counterpart, for a home, of the machine module `activation-marker`:
# see there for why.
#
# A step of the activation of the home writes the identity of the
# childless evaluation of the home, its activation package without the
# configurations declared inside it, into a file in the state directory
# of the user, `$XDG_STATE_HOME/caisson/markers/home-manager-<name>.json`.
# A configuration declared inside the home, such as an nvf
# configuration, compares that file with the identity it was built for
# when it is activated by hand. The step runs after the files of the
# home are linked, so a configuration the home activates after it reads
# the identity of the generation being activated.
#
# caisson's `default` home-manager module imports this module. The file
# is written only when the home has a configuration declared inside it
# that checks it, and not in the childless evaluation.
{ ... }:
{
  config,
  lib,
  pkgs,
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
    home.activation.caissonActivationMarker = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe' pkgs.coreutils "install"} -D -m 0644 ${pkgs.writeText "caisson-marker.json" marker.text} "${marker.path}"
    '';
  };
}
