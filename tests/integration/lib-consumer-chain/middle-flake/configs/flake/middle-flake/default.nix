# SPDX-License-Identifier: MIT
{ ... }:
{ ... }:
{
  systems = [ "x86_64-linux" ];

  caisson = {
    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    modules.flake.exported = modules: { inherit (modules) default; };
  };
}
