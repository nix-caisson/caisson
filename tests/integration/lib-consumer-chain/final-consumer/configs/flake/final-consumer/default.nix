# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.parent.flakeModules.default
    inputs.middle-flake.flakeModules.default
  ];

  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "final-consumer";

  perSystem =
    { pkgs, ... }:
    {
      checks.lib-consumer-chain-success =
        assert config.middleChain.moduleLoaded;
        assert lib.middleChain.closure.hasMiddleMarker;
        assert !(lib.middleChain.closure.hasFinalMarker);
        assert lib.middleChain.closure.hasCaisson;
        pkgs.runCommand "lib-consumer-chain-success" { } "touch $out";
    };
}
