# SPDX-License-Identifier: MIT
#
# A module with which a machine records what it applied, so that the
# configurations declared inside it can detect drift.
#
# Why
#
# A machine activates the configurations declared inside it: homes,
# hjem configurations, and the others that have an activation. A user
# can also activate such a configuration by hand, built from the source
# the user has checked out, for example with `home-manager switch`.
# That source can describe a different machine than the one that is
# applied: the user changed the machine and has not switched it yet, or
# the checkout is older than the machine. A configuration declared
# inside a machine reads settings of the machine, so it was then built
# for a machine that is not the one it is activated on.
#
# What the file holds
#
# The module writes `/etc/caisson/marker.json`, with one field,
# `identity`: the SHA-256 digest of the store path of the system that
# the childless evaluation of this machine builds, which is the
# evaluation without the configurations declared inside it. Computing
# the store path evaluates that system and builds nothing, and the
# digest names no store path, so the file depends on nothing. Changing
# one of the configurations declared inside leaves the identity the
# same; changing anything else about the machine changes it.
#
# A configuration declared inside the machine reads the same childless
# evaluation through its own manifest, so it computes the same identity
# from the same source. Its activation compares the two
# (`lib.caisson.integrations.driftCheckOf`), and warns when they differ.
# When the machine activates it, the file already belongs to the
# generation being activated, and the two are equal.
#
# The module is registered for the `nixos`, `darwin` and
# `systemManager` classes, under the same name, and the `default`
# module of each imports it. The file is written only when the machine
# has a configuration declared inside it that checks it, because
# computing the identity evaluates the machine a second time. It is not
# written in the childless evaluation, and not in an evaluation without
# `environment.etc`, which the nixos-minimal integration can produce.
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

  # The core module of the class of this evaluation, which declares
  # `caisson.exports`.
  coreModule =
    {
      darwin = closure-lib.caisson.modules.darwin.core;
      system-manager = closure-lib.caisson.modules.systemManager.core;
    }
    .${evalManifest.type or "nixos"} or closure-lib.caisson.modules.nixos.core;

  checked = builtins.any (selection.checksMarkerOf evalManifest) config.caisson.exports.configurations;

  marker = selection.markerOf evalManifest;
in
{
  imports = [ coreModule ];

  # `optionalAttrs` and not `mkIf` decides whether the option is defined
  # at all: a definition under `mkIf false` is still a definition, and
  # NixOS refuses a definition of an option that no module declares.
  config = lib.optionalAttrs hasEtc (
    lib.mkIf (!evalManifest.childless && checked && marker != null) {
      environment.etc."caisson/marker.json".text = marker.text;
    }
  );
}
