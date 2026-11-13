# SPDX-License-Identifier: MIT
#
# The configuration of the flake-parts caisson top: the shared
# configuration of what caisson exports, declared inside this caisson
# top under the name it is registered by (configs/structural/impl),
# the flake-parts configuration that holds the checks
# (configs/flake/checks), and the formatter partition that only a
# flake evaluation carries. What the shared configuration exports is
# passed up into the exports of this caisson top, and from there into
# the flake outputs.
{ closure-lib, ... }:
{ config, lib, ... }:
let
  manifest = lib.caisson-core.evalManifest;
in
{

  imports = [
    # flake-parts' partitions module, from the flake-parts input of
    # this flake's dependencies (a module file; it binds no library).
    closure-lib.caisson.dependencies.flake-parts.flakeModules.partitions
    ./partitions
  ];

  debug = false;

  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };

  # The checks of caisson, with the pins of tests/dependencies that
  # only the checks need. The caisson top gathers the checks of every
  # configuration declared inside it into its `checks` output,
  # whatever `exported` selects. This selector passes the
  # configuration up to nothing, so a flake that reads the exports of
  # caisson evaluates neither the configuration nor its pins: the
  # configuration is evaluated when the `checks` output, the
  # `containerTests` output or the `nestedVmTests` output of caisson
  # is read.
  caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
    inherit (lib.caisson.pins.flake-compat ../../../tests/dependencies) dependencies;
  };
  caisson.flake-parts.exported = _: { };

  # The tests that are not checks, which the workflows build by name,
  # from the outputs of the configuration that holds the checks. They
  # are read in the full evaluation of this caisson top, which holds
  # that configuration.
  flake = lib.mkIf (!manifest.childless) {
    inherit (config.caisson.flake-parts.configurations.checks.outputs.flake)
      containerTests
      nestedVmTests
      ;
  };

  # Each module that caisson exports reads the options under `caisson`
  # or the library under `lib.caisson`, so it works only inside an
  # evaluation that caisson makes. `mkLib` reads these modules from
  # the manifest when `projects` holds caisson. None of them is
  # published in the `modules` output.
  caisson.flakeOutputs.modules = _: { };

}
