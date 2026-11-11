# SPDX-License-Identifier: MIT
#
# A module with which a NixOS, nix-darwin or system-manager
# configuration records what it applied, so that the configurations
# declared inside it can detect drift.
#
# Why
#
# A NixOS configuration activates the configurations declared inside
# it: home-manager configurations, hjem configurations, and the others
# that have an activation. A user can also activate such a
# configuration by hand, built from the source the user has checked
# out, for example with `home-manager switch`. That source can hold a
# different version of the NixOS configuration than the version that is
# applied: the user changed the NixOS configuration and has not switched
# to it yet, or the checkout is older than the applied version. A
# configuration declared inside a NixOS configuration reads settings of
# the NixOS configuration, so it was then built for a version that is
# not the version applied on the computer it is activated on.
#
# What the file holds
#
# The module writes `/etc/caisson/marker.json`, with the field
# `identity`: the SHA-256 digest of the store path of the system that
# the childless evaluation of this configuration builds, the
# evaluation without the configurations declared inside it. Computing
# the store path evaluates that system and builds nothing, and the
# digest names no store path, so the file depends on nothing. Changing
# a configuration declared inside leaves the identity the same;
# changing anything else about this configuration changes it.
#
# When this configuration sets profiles of a configuration declared
# inside it, such as the packages of a home-manager configuration that
# sets `caisson.useUserPackages`, the file also holds `profiles`: for
# each such configuration, by the name of the marker file of that
# configuration, the digest of what each profile holds
# (`lib.caisson.integrations.machineProfilesOf`). The identity leaves
# those configurations out, so these digests are what tells a
# configuration built from another version that the switch set its
# profile to something else.
#
# A configuration declared inside this configuration reads the result
# of the same childless evaluation through the manifest of that
# configuration, so it computes the same identity from the same source.
# Its activation compares the two
# (`lib.caisson.integrations.driftCheckOf`), and warns when they differ.
# When this configuration activates it, the file already belongs to the
# generation being activated, and the two are equal.
#
# The module is registered for the `nixos`, `darwin` and
# `systemManager` classes, under the same name, and the `default`
# module of each imports it. The file is written only when the
# configuration has a configuration declared inside it that checks it,
# because computing the identity runs the childless evaluation. It is
# not written in the childless evaluation, and not in a configuration
# without `environment.etc`, which the nixos-minimal integration can
# produce.
{ closure-lib, ... }:
{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  hasEtc = options ? environment && options.environment ? etc;

  # The core module of the class of this configuration, which declares
  # `caisson.exports`.
  coreModule =
    {
      darwin = closure-lib.caisson.modules.darwin.core;
      system-manager = closure-lib.caisson.modules.systemManager.core;
    }
    .${evalManifest.type or "nixos"} or closure-lib.caisson.modules.nixos.core;

  checking = builtins.filter (selection.checksMarkerOf evalManifest) config.caisson.exports.configurations;
  checked = checking != [ ];

  marker = selection.markerOf evalManifest;

  # The profiles this configuration sets for the configurations that check its
  # marker (`machineProfilesOf`), by the name of the marker file of each
  # configuration.
  profiles = builtins.listToAttrs (
    builtins.concatMap (
      entry:
      let
        digests = selection.machineProfilesOf entry.manifest;
      in
      if digests == { } then
        [ ]
      else
        [
          {
            name = selection.markerFileName entry.manifest;
            value = digests;
          }
        ]
    ) checking
  );

  text =
    if profiles == { } then
      marker.text
    else
      builtins.toJSON {
        inherit (marker) identity;
        inherit profiles;
      };
in
{
  imports = [ coreModule ];

  # `optionalAttrs` and not `mkIf` decides whether the option is defined
  # at all: a definition under `mkIf false` is still a definition, and
  # NixOS refuses a definition of an option that no module declares.
  config = lib.optionalAttrs hasEtc (
    lib.mkIf (!evalManifest.childless && checked && marker != null) {
      environment.etc."caisson/marker.json".text = text;
    }
  );
}
