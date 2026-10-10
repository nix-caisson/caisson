# SPDX-License-Identifier: MIT
#
# A home-manager module for a home that is declared inside a NixOS
# configuration. When the home is activated, it warns if the home was
# built for a NixOS configuration that differs from the machine that is
# running.
#
# Why
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
# How
#
# The machine records which NixOS configuration it is running, in
# `/etc/caisson-home-manager/source.json`. The NixOS module
# `home-manager-source-marker` writes that file. Its field
# `baseSystemOutPath` is the store path of the system of the NixOS
# configuration as its childless evaluation builds it, which is the
# evaluation that leaves out the homes.
#
# This module computes the same path from the source the home is built
# from. It reads the childless evaluation of the NixOS configuration
# through the manifest of the home. The activation of the home
# compares the path with the path in the file, and prints a warning
# when they differ or when the file is missing. It does not stop the
# activation.
#
# When the machine activates the home itself, the file already belongs
# to the generation that is being activated, so the paths are equal.
#
# Cost
#
# Building the activation package of the home evaluates the system of
# the childless evaluation of the NixOS configuration.
#
# A NixOS configuration adds this module to the modules that the homes
# declared inside it import by default. caisson's `default` NixOS
# module does that, through `caisson.forChildren`. A home that passes
# `moduleImports` selects its modules itself, and gets this module
# only if it lists it. The module reads the machine through the
# manifest of the home, so it can only be imported by a home that has
# a NixOS configuration above it.
{ ... }:
# `lib` is the library of the home, and `config` is the configuration
# of the home.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  # The manifest of the childless evaluation of the NixOS configuration
  # the home is declared inside.
  machine = lib.caisson.evalManifest.nearest.nixos;

  # The store path of the system of that evaluation, as a plain string.
  # A string that refers to the system would make the home depend on
  # the system, and building the home would then build the system.
  # It is null for a NixOS configuration that builds no system, which
  # the nixos-minimal integration can produce.
  expected =
    if machine.outputs ? toplevel then
      builtins.unsafeDiscardStringContext machine.outputs.toplevel.outPath
    else
      null;

  marker = "/etc/caisson-home-manager/source.json";
  jq = lib.getExe' pkgs.jq "jq";
in
{
  options.caisson.home-manager.machineDrift.warn = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether the activation of this home warns when the home was built
      for a NixOS configuration that differs from the machine that is
      running.

      The machine records the NixOS configuration it runs in
      `/etc/caisson-home-manager/source.json`. The activation compares
      that record with the NixOS configuration in the source this home
      was built from. The comparison leaves the homes out, so a change
      to a home does not cause a warning.
    '';
  };

  config = lib.mkIf (config.caisson.home-manager.machineDrift.warn && expected != null) {
    home.activation.caissonMachineDrift = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      if [ ! -f ${marker} ]; then
        echo "WARNING: ${marker} does not exist." >&2
        echo "  This home is declared inside the NixOS configuration \`${machine.name}\`," >&2
        echo "  and the machine that is running does not record which NixOS configuration it runs." >&2
        echo "  Switch the machine to the NixOS configuration this home was built with." >&2
      else
        _caissonRunning="$(${jq} -r '.baseSystemOutPath // empty' < ${marker})"
        if [ "$_caissonRunning" != ${lib.escapeShellArg expected} ]; then
          echo "WARNING: this home was built for a NixOS configuration that differs from the machine that is running." >&2
          echo "  the machine runs (homes left out):" >&2
          echo "    ''${_caissonRunning:-unknown}" >&2
          echo "  this home was built for (homes left out):" >&2
          echo "    ${expected}" >&2
          echo "  Switch the machine to the NixOS configuration this home was built with," >&2
          echo "  or set \`caisson.home-manager.machineDrift.warn = false\` in the home." >&2
        fi
      fi
    '';
  };
}
