# SPDX-License-Identifier: MIT
#
# The checks configuration of the producer. Its dependencies throw when
# they are read, so evaluating this configuration throws.
{ ... }:
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.producer-check = pkgs.runCommand "producer-check" { } "touch $out";
    };
}
