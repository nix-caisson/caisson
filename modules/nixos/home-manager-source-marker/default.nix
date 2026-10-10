# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration that has homes declared
# inside it. The module writes a file on the machine. The file names
# the NixOS configuration that the machine is running. A home reads
# the file when the home is activated. The home prints a warning if
# the home was built for a different NixOS configuration.
#
# Why a home needs this
#
# The machine activates the homes declared inside its NixOS
# configuration. The user can also activate such a home by hand, with
# `home-manager switch`. `home-manager switch` builds the home from
# the source the user has checked out.
#
# That source can describe a different machine than the machine that
# is running. This happens when the user changed the NixOS
# configuration and has not switched the machine yet. It also happens
# when the checkout is older than the machine.
#
# A home reads settings of its machine. A home built from such a
# source has read the settings of a machine that is not the machine
# the home is activated on.
#
# What the file holds
#
# The file is `/etc/caisson-home-manager/source.json`. It has one
# field, `baseSystemOutPath`, which is a store path. The store path is
# the system that the childless evaluation of this NixOS configuration
# builds.
#
# The childless evaluation is the evaluation of the NixOS
# configuration that leaves out the configurations declared inside the
# NixOS configuration. The homes are among those configurations. So
# the store path does not depend on the homes. Changing a home leaves
# the store path the same. Changing anything else about the machine
# changes the store path.
#
# A home declared inside the NixOS configuration can read the same
# childless evaluation through the manifest of the home. The home
# therefore computes the same store path from the same source. The
# home-manager module `nixos-source-marker` compares the store path
# the home computed with the store path in the file.
#
# Cost
#
# To write the file, the module evaluates the system of the childless
# evaluation. That is a second evaluation of the whole NixOS
# configuration. The module writes the file only when at least one
# home is declared inside the NixOS configuration. A machine with no
# homes does not pay for the second evaluation.
#
# Where the module defines nothing
#
# The module defines nothing in the childless evaluation, because the
# childless evaluation has no homes.
#
# The module also defines nothing in a NixOS evaluation that has no
# `environment.etc` option. The nixos-minimal integration can produce
# such an evaluation, and such an evaluation has nowhere to put the
# file.
{ ... }:
{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib.caisson) evalManifest;

  hasEtc = options ? environment && options.environment ? etc;

  # True for a home that belongs to this machine.
  #
  # `entry.path` is a list of `{ type, name }` segments. The list is
  # the path from this NixOS configuration to the configuration of the
  # entry. A NixOS configuration on that path is a machine inside this
  # machine. A home below such a machine belongs to that machine and
  # not to this machine.
  isHomeOfThisMachine =
    entry:
    entry.manifest.type == "home-manager"
    && !(builtins.any (segment: segment.type == "nixos") (lib.lists.init entry.path));

  hasHomes = builtins.any isHomeOfThisMachine config.caisson.exports.configurations;

  # The store path is written as a plain string. A string that refers
  # to the system would make the file depend on the system. The
  # machine would then have to build the system of the childless
  # evaluation, only to write the name of that system into the file.
  baseSystemOutPath = builtins.unsafeDiscardStringContext evalManifest.childlessManifest.outputs.toplevel.outPath;
in
{
  # `optionalAttrs` and not `mkIf` decides whether the option is
  # defined at all. A definition under `mkIf false` is still a
  # definition, and NixOS refuses a definition of an option that no
  # module declares.
  config = lib.optionalAttrs hasEtc (
    lib.mkIf (!evalManifest.childless && hasHomes) {
      environment.etc."caisson-home-manager/source.json".text = builtins.toJSON {
        inherit baseSystemOutPath;
      };
    }
  );
}
