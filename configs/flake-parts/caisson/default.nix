# SPDX-License-Identifier: MIT
{ ... }:
{ inputs, config, ... }:
{

  imports = [
    inputs.flake-parts.flakeModules.partitions
    ./partitions
  ];

  partitionedAttrs.checks = "checks";

  systems = [ "x86_64-linux" ];

  debug = false;

  caisson = {

    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    modules.flake.exported = modules: { inherit (modules) default; };

    lib.export.enabled = true;

  };

}
