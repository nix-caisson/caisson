# SPDX-License-Identifier: MIT
{ ... }:
{ config, lib, ... }:
let
  configName = config.caisson.configInfo.configName;
in
{

  options.caisson.lib.export.enabled = lib.mkEnableOption "lib export";

  config = {
    caisson.lib.export.enabled = lib.mkDefault false;

    flake.lib =
      if config.caisson.lib.export.enabled then
        assert lib.assertMsg (configName != null)
          "caisson.lib.export.enabled is true but caisson.configInfo.configName is not set. Set configName or disable lib export.";
        lib.${configName}
      else
        { };
  };
}
