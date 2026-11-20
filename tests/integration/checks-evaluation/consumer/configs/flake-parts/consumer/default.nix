# SPDX-License-Identifier: MIT
#
# The flake of the consumer. Its check builds when the consumer reads
# the exports of the producer, and the producer evaluates neither its
# checks configuration nor the dependencies of that configuration, which
# throw when they are read. Reading the `checks` output of the producer
# reads them, which shows that the dependencies would throw.
{ ... }:
{ inputs, lib, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, ... }:
    {
      checks.consumer =
        assert lib.caisson.libOverlays ? "producer/default";
        assert !(builtins.tryEval (builtins.attrNames inputs.producer.checks.x86_64-linux)).success;
        pkgs.runCommand "checks-evaluation-consumer" { } "touch $out";
    };
}
