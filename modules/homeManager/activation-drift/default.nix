# SPDX-License-Identifier: MIT
#
# A home-manager module with which a home-manager configuration
# declared inside another configuration that has an activation, such
# as a NixOS, darwin or system-manager machine, detects drift when it
# is activated.
#
# The user can activate such a home-manager configuration by hand,
# with `home-manager switch`, built from the source the user has
# checked out. That source can describe a different version of the
# configuration above than the version that is applied. The configuration
# above records what it applied in a marker (the module
# `activation-marker` of its class). A step of the activation of the
# home-manager configuration compares that marker with the identity of
# the configuration above as the home-manager configuration was built
# for it, and prints a warning when they differ or when the marker is
# missing. The step does not stop the activation. When the
# configuration above activates the home-manager configuration, its
# marker belongs to the generation being activated, and the step prints
# nothing.
#
# The check is `lib.caisson.integrations.driftCheckOf`, the same check
# every configuration with an activation runs against the nearest
# configuration above it that has one. A home-manager configuration
# with no such configuration above it has nothing to check, and the
# module then defines no step.
#
# caisson's `default` home-manager module imports this module.
{ ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  check = lib.caisson.integrations.driftCheckOf {
    jq = lib.getExe' pkgs.jq "jq";
    optionText = "`caisson.drift.warn`";
  } lib.caisson.evalManifest;
in
{
  options.caisson.drift.warn = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether the activation of this home-manager configuration prints
      a warning when the home-manager configuration was built for a
      version of the configuration it is declared inside that differs
      from the version that is applied.

      The configuration above, such as the machine, records what it
      applied in a marker file. The activation of this home-manager
      configuration compares the marker with the configuration above as
      it is in the source this home-manager configuration was built
      from. The comparison leaves out the configurations declared
      inside the configuration above, so a change to a home-manager
      configuration does not cause a warning.
    '';
  };

  config = lib.mkIf (config.caisson.drift.warn && check != "") {
    home.activation.caissonDrift = lib.hm.dag.entryBefore [ "writeBoundary" ] check;
  };
}
