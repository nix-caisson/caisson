# SPDX-License-Identifier: MIT
{ ... }:
{ config, lib, ... }:
let
  configName = config.caisson.configInfo.configName;
in
{

  options.caisson.lib = {

    export.enabled = lib.mkEnableOption "lib export";

    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
      description = ''
        Function that selects which parts of the composed library to
        publish as the flake's `lib` output. Receives the composed
        library; defaults to the flake's own namespace.
      '';
      default =
        composedLib:
        assert lib.assertMsg (configName != null)
          "caisson.lib.export.enabled is true but caisson.configInfo.configName is not set. Set configName or disable lib export.";
        composedLib.${configName};
      defaultText = "composedLib: composedLib.\${configName}";
    };

  };

  config = {
    caisson.lib.export.enabled = lib.mkDefault false;

    flake.lib = if config.caisson.lib.export.enabled then config.caisson.lib.exported lib else { };
  };
}
