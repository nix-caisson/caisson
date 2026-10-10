# SPDX-License-Identifier: MIT
#
# A home-manager module for a home that is declared inside a NixOS
# configuration. The module adds a step to the activation of the home.
# The step prints a warning if the home was built for a NixOS
# configuration that differs from the machine that is running.
#
# Why
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
# How
#
# The machine has a file, `/etc/caisson-home-manager/source.json`,
# that names the NixOS configuration the machine is running. The NixOS
# module `home-manager-source-marker` writes the file. The field
# `baseSystemOutPath` of the file is a store path. The store path is
# the system that the childless evaluation of the NixOS configuration
# builds. The childless evaluation is the evaluation that leaves out
# the homes.
#
# This module computes the same store path from the source the home is
# built from. The module reads the childless evaluation of the NixOS
# configuration through the manifest of the home.
#
# The step in the activation compares the store path this module
# computed with the store path in the file. The step prints a warning
# when the two store paths differ. The step also prints a warning when
# the file does not exist. The step does not stop the activation.
#
# When the machine activates the home, the file on the machine already
# belongs to the generation that is being activated. The two store
# paths are then equal, and the step prints nothing.
#
# Cost
#
# Building the activation package of the home evaluates the system of
# the childless evaluation of the NixOS configuration.
#
# Which homes import this module
#
# caisson's `default` NixOS module gives this module to the homes
# declared inside the NixOS configuration, through
# `caisson.forChildren`. Such a home imports this module by default.
# A home that passes `moduleImports` selects its modules itself. That
# home imports this module only if the home lists it.
#
# The module reads the NixOS configuration through the manifest of the
# home. A home with no NixOS configuration above it cannot import this
# module.
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

  # The store path of the system that the childless evaluation builds.
  #
  # The store path is kept as a plain string. A string that refers to
  # the system would make the home depend on the system. Building the
  # home would then build the system.
  #
  # The value is null for a NixOS configuration that builds no system.
  # The nixos-minimal integration can produce such a NixOS
  # configuration.
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
      Whether the activation of this home prints a warning when the
      home was built for a NixOS configuration that differs from the
      machine that is running.

      The file `/etc/caisson-home-manager/source.json` on the machine
      names the NixOS configuration the machine is running. The
      activation of this home compares the file with the NixOS
      configuration in the source this home was built from.

      The comparison leaves the homes out. A change to a home does not
      cause a warning.
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
