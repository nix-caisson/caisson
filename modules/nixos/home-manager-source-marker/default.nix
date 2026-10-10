# SPDX-License-Identifier: MIT
#
# A NixOS module that records, on the machine, which NixOS
# configuration the machine is running. A home declared inside the
# NixOS configuration reads the record when it is activated, and warns
# when it was built for a different NixOS configuration.
#
# Why a home needs this
#
# A home declared inside a NixOS configuration is activated by the
# machine, and the user can also activate it by hand with
# `home-manager switch`. The second way builds the home from whatever
# source the user has checked out. That source may describe a machine
# that differs from the machine that is running: the user changed the
# NixOS configuration and has not switched the machine yet, or the
# checkout is older than the machine. A home reads settings of its
# machine, so a home built from such a source can disagree with the
# machine it is activated on.
#
# What is recorded
#
# The module writes `/etc/caisson-home-manager/source.json`. The field
# `baseSystemOutPath` is the store path of the system of this NixOS
# configuration as its childless evaluation builds it. The childless
# evaluation leaves out the configurations declared inside the NixOS
# configuration, the homes among them. So the path identifies the
# machine apart from its homes, and a change to a home does not change
# it.
#
# A home declared inside the NixOS configuration reads the same
# childless evaluation through its manifest, and so computes the same
# path from the same source. The home-manager module
# `nixos-source-marker` compares the two when the home is activated.
#
# The other fields say where the record came from: the name of the
# NixOS configuration, the source tree of the flake, and the nixpkgs
# of the package set.
#
# Cost
#
# Writing the record evaluates the system of the childless evaluation,
# which is a second evaluation of the whole NixOS configuration. The
# module writes the record only when at least one home is declared
# inside the NixOS configuration, so a machine with no homes does not
# pay for it.
#
# Where the module defines nothing
#
# The childless evaluation has no homes, so there the module defines
# nothing. A NixOS evaluation that has no `environment.etc` option,
# which the nixos-minimal integration can produce, cannot hold the
# file, so there the module also defines nothing.
{ ... }:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest libManifest;

  hasEtc = options ? environment && options.environment ? etc;

  # True for a home that belongs to this machine. `entry.path` is the
  # path from this NixOS configuration to the configuration of the
  # entry, a list of `{ type, name }` segments. A NixOS configuration
  # on the path is a machine inside this machine, and the home belongs
  # to it.
  isHomeOfThisMachine =
    entry:
    entry.manifest.type == "home-manager"
    && !(builtins.any (segment: segment.type == "nixos") (lib.lists.init entry.path));

  hasHomes = builtins.any isHomeOfThisMachine config.caisson.exports.configurations;

  outPathOf =
    value:
    if value == null then
      null
    else if builtins.isAttrs value && value ? outPath then
      value.outPath
    else
      toString value;

  # The store path is recorded as a plain string. A string that refers
  # to the system would make the file depend on that system, and the
  # machine would then build a second system only to name it.
  baseSystemOutPath = builtins.unsafeDiscardStringContext evalManifest.childlessManifest.outputs.toplevel.outPath;

  record = {
    schemaVersion = 3;
    hostKind = "nixos";
    hostName = evalManifest.name;
    profileName = "hosted";
    selfOutPath = outPathOf (libManifest.root or null);
    nixpkgsOutPath = outPathOf (pkgs.path or null);
    homeManagerOutPath = null;
    inherit baseSystemOutPath;
  };
in
{
  # `optionalAttrs` and not `mkIf` decides whether the option is
  # defined at all. A definition under `mkIf false` is still a
  # definition, and NixOS refuses a definition of an option that no
  # module declares.
  config = lib.optionalAttrs hasEtc (
    lib.mkIf (!evalManifest.childless && hasHomes) {
      environment.etc."caisson-home-manager/source.json".text = builtins.toJSON (
        record // { fingerprint = builtins.hashString "sha256" (builtins.toJSON record); }
      );
    }
  );
}
