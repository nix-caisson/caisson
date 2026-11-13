# SPDX-License-Identifier: MIT
#
# The flake of the producer: a flake-parts configuration that holds its
# checks, declared with dependencies that throw when they are read, and
# a selector that passes that configuration up to nothing. The consumer
# lists the producer in `projects` and reads its exports, which the
# configuration that holds the checks takes no part in. Reading the
# `checks` output of the producer reads those dependencies and throws.
{ ... }:
{ lib, ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
    dependencies = throw "checks-evaluation: the dependencies of the checks configuration of the producer were read";
  };
  caisson.flake-parts.exported = _: { };
}
