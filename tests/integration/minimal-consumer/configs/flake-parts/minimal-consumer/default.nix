# SPDX-License-Identifier: MIT
{ ... }:
{ pkgs, ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "minimal-consumer";

  perSystem =
    { pkgs, ... }:
    {
      checks.minimal-consumer-success = pkgs.runCommand "minimal-consumer-success" { } ''
        echo 'minimal consumer composed successfully' > $out
      '';
    };
}
