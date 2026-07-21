# SPDX-License-Identifier: MIT
{ ... }:
{ inputs, ... }:
{
  imports = [ inputs.parent.flakeModules.default ];

  systems = [ "x86_64-linux" ];

  caisson = {
    configInfo.configName = "middle-chain";

    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    modules.flake.exported = modules: { inherit (modules) default; };
  };
}
