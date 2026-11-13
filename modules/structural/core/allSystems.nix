# SPDX-License-Identifier: MIT
#
# The results of `perSystem` (./perSystem.nix), one for each system
# the children of the structural configuration are evaluated for: the systems `caisson.forChildren.systems` states, and otherwise
# the systems the configuration is evaluated for.
{ config, lib, ... }:
let
  manifest = lib.caisson-core.evalManifest;
  stated = config.caisson.forChildren.systems;
  inherited = if manifest == null then null else manifest.systems or null;
  systems =
    if stated != null then
      stated
    else if inherited != null then
      inherited
    else
      [ ];
in
{
  options.allSystems = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    internal = true;
    readOnly = true;
    description = ''
      The result of `perSystem` for each system the children of the
      structural configuration are evaluated for, by system.
    '';
  };

  config.allSystems = lib.genAttrs systems config.perSystem;
}
