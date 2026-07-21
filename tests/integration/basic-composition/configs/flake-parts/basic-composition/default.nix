# SPDX-License-Identifier: MIT
{ ... }:
{ pkgs, ... }:
{
  systems = [ "x86_64-linux" ];
  perSystem =
    { pkgs, ... }:
    {
      checks.composition-success =
        pkgs.runCommand "composition-success" { }
          "echo 'composed successfully' > $out";
    };
}
