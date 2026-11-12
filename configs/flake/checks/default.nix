# SPDX-License-Identifier: MIT
#
# The checks of caisson: a flake-parts configuration declared inside
# the flake-parts caisson top (configs/flake/caisson), whose
# dependencies are those of the caisson top with the pins of
# tests/dependencies beside them. The caisson top gathers the checks
# declared here into its `checks` output. A flake that uses caisson
# reads nothing of this configuration, so it locks none of the pins of
# tests/dependencies.
#
# `inputs` are those dependencies. Where tests/dependencies names a
# dependency that flake.lock pins as well (caisson-core, flake-parts,
# nixpkgs-lib), `inputs` hold the pin of flake.lock. `self` is the
# flake of this configuration, and `self.outPath` is the source tree of
# caisson.
{ ... }:
{
  inputs,
  lib,
  self,
  ...
}:
let

  # The flake of caisson, evaluated from source by
  # `lib.caisson.callConsumerFlake` over the inputs of this
  # configuration: its inputs are those flake.lock pins. The checks
  # read caisson from it as a flake that lists caisson as an input
  # reads it.
  caisson = lib.caisson.callConsumerFlake {
    path = self.outPath;
    pool = inputs;
    sourceInfo = builtins.removeAttrs self.sourceInfo [ "dirty" ];
  };

  # The inputs of the system-manager tests: the dependency pool with
  # `caisson` set to the flake of caisson.
  testInputs = inputs // {
    inherit caisson;
  };

in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  # The darwin check is the only check for aarch64-darwin.
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
  perSystem =
    { system, ... }:
    let
      # Consumer-style flakes, evaluated from source with inputs
      # resolved by name from this pool (see callConsumerFlake). A test
      # flake that follows `deps/<name>` reads `<name>` of the inputs of
      # `deps`. `deps` is the flake of this configuration, whose inputs
      # are those of this configuration and whose out path is the
      # source tree of caisson. nix-unit takes that out path as the
      # tree of the `deps` input of the unit test flake.
      consumerPool = {
        inherit (inputs)
          flake-parts
          nixpkgs
          nixpkgs-lib
          nix-unit
          ;
        deps = self;
        parent = caisson;
      };
      callConsumer =
        args:
        lib.caisson.callConsumerFlake (
          {
            pool = consumerPool;
          }
          // args
        );

      # Integration Tests
      integrationOutputs = callConsumer {
        path = self.outPath + "/tests/integration/basic-composition";
      };

      minimalConsumerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/minimal-consumer";
      };

      moduleClassExportOutputs = callConsumer {
        path = self.outPath + "/tests/integration/module-class-export";
      };

      libConsumerChainMiddleOutputs = callConsumer {
        path = self.outPath + "/tests/integration/lib-consumer-chain/middle-flake";
        overrides.middleMarker = {
          source = "middle";
        };
      };

      libConsumerChainFinalOutputs = callConsumer {
        path = self.outPath + "/tests/integration/lib-consumer-chain/final-consumer";
        overrides = {
          middle-flake = libConsumerChainMiddleOutputs;
          finalMarker = {
            source = "final";
          };
        };
      };

      nixpkgsConsumerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/nixpkgs-consumer";
      };

      nixpkgsOverlayExportOutputs = callConsumer {
        path = self.outPath + "/tests/integration/nixpkgs-overlay-export";
      };

      nixpkgsNoPkgSetsOutputs = callConsumer {
        path = self.outPath + "/tests/integration/nixpkgs-no-pkg-sets";
      };

      nixpkgsPkgSetsOutputs = callConsumer {
        path = self.outPath + "/tests/integration/nixpkgs-pkg-sets";
      };

      nixpkgsLibOnlyOutputs = callConsumer {
        path = self.outPath + "/tests/integration/nixpkgs-lib-only";
      };

      # A project that registers package overlays, and a consumer
      # that takes them through `projects`.
      pkgOverlaysProducerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/pkg-overlays-registry/producer";
      };

      pkgOverlaysConsumerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/pkg-overlays-registry/consumer";
        overrides.producer = pkgOverlaysProducerOutputs;
      };

      # A project whose checks configuration adds dependencies that
      # throw when they are read, and a consumer that lists it in
      # `projects`.
      checksEvaluationProducerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/checks-evaluation/producer";
      };

      checksEvaluationConsumerOutputs = callConsumer {
        path = self.outPath + "/tests/integration/checks-evaluation/consumer";
        overrides.producer = checksEvaluationProducerOutputs;
      };

      # Unit Tests
      unitTestOutputs = callConsumer {
        path = self.outPath + "/tests/unit";
      };

      # Example: Literate Flake
      exampleOutputs = callConsumer {
        path = self.outPath + "/examples/literate-flake";
        overrides.caisson = caisson;
      };

      pkgs = inputs.nixpkgs.legacyPackages.${system};

      evalWeight = import (self.outPath + "/lib-overlays/tooling/eval-weight") {
        lib = pkgs.lib;
      };
      evalWeightArgs = {
        caisson = self.outPath;
        caisson-core = inputs.caisson-core.outPath;
        flake-parts = inputs.flake-parts.outPath;
        nixpkgs = inputs.nixpkgs.outPath;
        nixpkgs-lib = inputs.nixpkgs-lib.outPath;
        inherit system;
      };
      evalWeightBaseline = self.outPath + "/tests/eval-weight/baseline.json";

      # The library the argument-error check evaluates against:
      # caisson's overlays and modules composed from store paths,
      # the way default.nix composes them, since the sandbox can
      # fetch nothing.
      argumentErrorsLib = ''
        let
          core = import ${inputs.caisson-core.outPath};
        in
        core.mkLib {
          dependencies.nixpkgs-lib = ${inputs.nixpkgs-lib.outPath};
          modules = lib: lib.caisson-core.mkModules ${self.outPath}/modules;
          libOverlays = lib: lib.caisson-core.mkLibOverlays ${self.outPath}/lib-overlays;
        }
      '';

      # The checks of a test flake for this system, without its check
      # `registries`. A test flake that is a caisson top has the check
      # `registries`, and the caisson top of caisson publishes the check
      # `registries` of caisson under that name.
      testChecksOf = outputs: builtins.removeAttrs outputs.checks.${system} [ "registries" ];

      # The checks for x86_64-linux.
      linuxChecks =
        testChecksOf integrationOutputs
        // testChecksOf minimalConsumerOutputs
        // testChecksOf moduleClassExportOutputs
        // testChecksOf libConsumerChainFinalOutputs
        // testChecksOf nixpkgsConsumerOutputs
        // testChecksOf nixpkgsOverlayExportOutputs
        // testChecksOf nixpkgsNoPkgSetsOutputs
        // testChecksOf nixpkgsPkgSetsOutputs
        // testChecksOf nixpkgsLibOnlyOutputs
        // testChecksOf pkgOverlaysProducerOutputs
        // testChecksOf pkgOverlaysConsumerOutputs
        // testChecksOf unitTestOutputs
        // {
          literate-flake-default = exampleOutputs.packages.${system}.default;
          literate-flake-greeting = exampleOutputs.packages.${system}.greeting;
          debug-disabled =
            assert !(caisson ? debug);
            pkgs.runCommand "debug-disabled" { } "touch $out";
          # The pinned-world suite, forced at evaluation time: the
          # caisson itself composed with the upstream pins of
          # tests/dependencies, so the check evaluates caisson
          # against the committed world. The drift workflow builds
          # this check alone over advanced pins.
          pinned-world =
            let
              suite = import (self.outPath + "/tests/pinned-world") {
                inputs = inputs // {
                  inherit caisson;
                };
              };
            in
            builtins.seq suite.summary (pkgs.runCommand "pinned-world" { } "touch $out");
          # The manifest file of a hjem configuration inside a NixOS
          # configuration and the units that activate it, built.
          # Building the manifest file checks it against the schema
          # of hjem with `cue vet`, so the file the NixOS
          # configuration activates is a file hjem's CLI accepts. Building the units runs shellcheck
          # on their scripts.
          hjem-system =
            let
              probe = import (self.outPath + "/tests/hjem-system") {
                inputs = inputs // {
                  inherit caisson;
                };
              };
              units = probe.top.nixosConfigurations.probe-nixos.config.systemd.units;
            in
            pkgs.linkFarm "hjem-system" (
              [
                {
                  name = "manifest-probe.json";
                  path = probe.inner.outputs.manifestFile;
                }
              ]
              ++
                builtins.map
                  (name: {
                    inherit name;
                    path = units.${name}.unit;
                  })
                  [
                    "hjem.target"
                    "hjem-prepare.service"
                    "hjem-activate@.service"
                    "hjem-reload@.service"
                    "hjem-update-state@.service"
                    "hjem-cleanup.service"
                  ]
            );
          # The warning of a drift check, printed by a real
          # activation and compared with the text it is written
          # to print.
          drift-message = import (self.outPath + "/tests/drift-message") {
            inputs = inputs // {
              inherit caisson;
            };
          };
          # The discovery program of a NixOps4 root, built and run
          # against recorded state dumps, with a stand-in for
          # NixOps4 that prints them (tests/nixops4-discovery).
          nixops4-discovery = import (self.outPath + "/tests/nixops4-discovery") {
            inputs = inputs // {
              inherit caisson;
            };
          };
          # A NixOS configuration booted in a VM that activates the
          # home-manager configurations, the hjem configurations
          # and the profiles declared inside it, and a standalone
          # hjem configuration, each through sequences of changes
          # (tests/activation-vm).
          activation-vm = import (self.outPath + "/tests/activation-vm") {
            inputs = inputs // {
              inherit caisson;
            };
          };
          # A NixOS test declared through the nixos-test
          # integration inside a NixOS configuration, run in a VM:
          # its node reads the NixOS configuration it is declared
          # inside (tests/nixos-test-vm).
          nixos-test-vm = import (self.outPath + "/tests/nixos-test-vm") {
            inputs = inputs // {
              inherit caisson;
            };
          };
          # A NixOS configuration booted in a VM that installs the packages of
          # the home-manager configurations that set
          # `caisson.useUserPackages`, through switches and a boot
          # (tests/user-packages-vm).
          user-packages-vm = import (self.outPath + "/tests/user-packages-vm") {
            inputs = inputs // {
              inherit caisson;
            };
          };
          # The argument error of every entry point comes from Nix
          # itself, raised at the call site with no frame of caisson
          # above it: the real evaluator runs each wrong call and the
          # script reads the trace, since nix-unit sees messages
          # alone. The evaluator runs the way nix-unit's does in
          # the sandbox, on a local store beside the real store.
          argument-errors =
            pkgs.runCommand "argument-errors"
              {
                nativeBuildInputs = [ pkgs.nix ];
              }
              ''
                export HOME="$(realpath .)"
                unset NIX_STORE
                export NIX_STORE_DIR=${builtins.storeDir}
                export NIX_REMOTE="$HOME/storedata"
                bash ${self.outPath}/tests/argument-errors/check.sh ${lib.escapeShellArg argumentErrorsLib} \
                  --impure --extra-experimental-features nix-command
                touch $out
              '';
          # The errors of deferred configurations and the NixOps4
          # integrations, read as text by the real evaluator, as
          # a tool that finalizes a deferred configuration reads
          # them. It runs as the argument-error check does, on
          # the same library.
          deferred-errors =
            pkgs.runCommand "deferred-errors"
              {
                nativeBuildInputs = [ pkgs.nix ];
              }
              ''
                export HOME="$(realpath .)"
                unset NIX_STORE
                export NIX_STORE_DIR=${builtins.storeDir}
                export NIX_REMOTE="$HOME/storedata"
                bash ${self.outPath}/tests/deferred-errors/check.sh ${lib.escapeShellArg argumentErrorsLib} \
                  ${inputs.nixops4.outPath} \
                  --impure --extra-experimental-features nix-command
                touch $out
              '';
          minimal-consumer-all-outputs = builtins.seq minimalConsumerOutputs.flakeModule (
            builtins.seq minimalConsumerOutputs.lib (
              pkgs.runCommand "minimal-consumer-all-outputs" { } "touch $out"
            )
          );
          eval-weight = evalWeight.mkCheck {
            inherit pkgs;
            name = "caisson";
            scenarios = {
              raw-flake-parts = {
                entry = self.outPath + "/tests/eval-weight/raw-flake-parts.nix";
                args = evalWeightArgs;
              };
              minimal-consumer = {
                entry = self.outPath + "/tests/eval-weight/minimal-consumer.nix";
                args = evalWeightArgs;
              };
            };
            gates = [
              # The framework's cost, isolated from nixpkgs churn:
              # this is the number that must not creep. It includes
              # an instantiation of flake-parts' library over the
              # composed lib, since the raw scenario's flake-parts is
              # built over the plain nixpkgs lib and is not shared,
              # and the evaluation of the structural configuration
              # declared inside the caisson top of caisson's flake, which reading
              # caisson's outputs pays.
              {
                name = "caisson-overhead";
                minuend = "minimal-consumer";
                subtrahend = "raw-flake-parts";
              }
              # Loose ceiling on the whole trivial consumer, mostly to
              # notice when a dependency bump shifts the ground under us.
              {
                name = "minimal-consumer-total";
                scenario = "minimal-consumer";
                maxGrowth = 0.25;
              }
            ];
            baseline =
              if builtins.pathExists evalWeightBaseline then
                builtins.fromJSON (builtins.readFile evalWeightBaseline)
              else
                null;
          };
        }
        # The same system-manager configuration and sequences as the
        # container tests below, in a VM of each distribution below,
        # booted from the cloud image of the distribution with its
        # kernel and its systemd, as `system-manager-vm-<distribution>`.
        # The systemd of these distributions needs a VM to start logind
        # and the other services the distribution ships with.
        // builtins.listToAttrs (
          builtins.map
            (distro: {
              name = "system-manager-vm-${distro}";
              value = import (self.outPath + "/tests/system-manager/vm.nix") {
                inputs = testInputs;
                inherit distro;
              };
            })
            [
              "ubuntu-22_04"
              "debian-12"
            ]
        );

      # The checks for aarch64-darwin: a nix-darwin configuration
      # declared through the darwin integration, built, which is the
      # system `darwin-rebuild` would build for it. The pinned-world
      # suite evaluates the same nix-darwin configuration on a Linux or
      # macOS machine; building it needs a darwin builder, so the
      # darwin job of the workflow builds it on a macOS runner.
      darwinChecks.darwin-system =
        let
          probe = import (self.outPath + "/tests/darwin-system") {
            inputs = inputs // {
              inherit caisson;
            };
          };
        in
        # The bare nix-darwin configuration, and the nix-darwin configuration with a home-manager
        # configuration and a hjem configuration inside it, whose
        # system holds the activation of the home-manager
        # configuration and the launchd agents of hjem. Beside them,
        # the manifests of a hjem configuration that is a caisson top, in the
        # versions v1 and v2, and the hjem CLI, with which the darwin
        # job applies it on the runner
        # (tests/darwin-system/hjem-standalone.sh).
        probe.pkgs.linkFarm "darwin-system" [
          {
            name = "probe";
            path = probe.toplevel;
          }
          {
            name = "family";
            path = probe.family.system;
          }
          {
            name = "hjem-standalone/manifest-v1.json";
            path = probe.pkgs.writeText "manifest-runner-v1.json" (
              builtins.toJSON (probe.standaloneHjemOf "v1").outputs.manifest
            );
          }
          {
            name = "hjem-standalone/manifest-v2.json";
            path = probe.pkgs.writeText "manifest-runner-v2.json" (
              builtins.toJSON (probe.standaloneHjemOf "v2").outputs.manifest
            );
          }
          {
            name = "hjem-standalone/hjem";
            path = probe.standaloneHjem.outputs.cli;
          }
          # The nix-darwin configuration for the runner in each
          # version, which the darwin job activates on the runner
          # (tests/darwin-system/runner-darwin.sh).
          {
            name = "runner-darwin/v1";
            path = (probe.runnerDarwinOf "v1").darwinConfigurations.runner-darwin.system;
          }
          {
            name = "runner-darwin/v2";
            path = (probe.runnerDarwinOf "v2").darwinConfigurations.runner-darwin.system;
          }
          # The activation package of the home-manager configuration
          # of `runner` in each version, which the script runs by
          # hand.
          {
            name = "runner-darwin/home-v1";
            path = (probe.runnerDarwinOf "v1").homeConfigurations."runner@runner-darwin".activationPackage;
          }
          {
            name = "runner-darwin/home-v2";
            path = (probe.runnerDarwinOf "v2").homeConfigurations."runner@runner-darwin".activationPackage;
          }
        ];

    in
    {
      # Duplicated in configs/flake/caisson/partitions/formatter.nix:
      # the formatter partition is a separate evaluation of the modules
      # of the caisson top, so sharing the settings would need more
      # wiring than the duplication. The check of the formatter is a
      # check for x86_64-linux.
      treefmt = {
        programs.nixfmt.enable = true;
        flakeCheck = system == "x86_64-linux";
      };
      checks =
        if system == "x86_64-linux" then
          linuxChecks
        else if system == "aarch64-darwin" then
          darwinChecks
        else
          { };
      # The checks of the consumer of tests/integration/checks-evaluation,
      # published as `checks-evaluation-<name>`. Evaluating them reads
      # the exports of the producer, whose checks configuration is
      # declared with dependencies that throw when they are read, as a
      # `nix flake check` of the consumer does.
      caisson.checks = lib.mkIf (system == "x86_64-linux") {
        checks-evaluation.top = checksEvaluationConsumerOutputs;
      };
    };

  # A system-manager configuration activated in a container of each
  # distribution of tests/system-manager/container-distros.nix,
  # through sequences of changes, as
  # `system-manager-<distribution>`. The container runs in the
  # build sandbox only where Nix runs with
  # `auto-allocate-uids = true`, so the tests are not checks
  # `nix flake check` builds; the workflow builds them by name. The
  # caisson top publishes them as its `containerTests` output.
  flake.containerTests.x86_64-linux =
    let
      distros = builtins.attrNames (
        import (self.outPath + "/tests/system-manager/container-distros.nix") {
          inputs = testInputs;
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
        }
      );
    in
    builtins.listToAttrs (
      builtins.map (distro: {
        name = "system-manager-${distro}";
        value = import (self.outPath + "/tests/system-manager/container.nix") {
          inputs = testInputs;
          inherit distro;
        };
      }) distros
    );

  # A guest of a caisson-microvm configuration on cloud-hypervisor,
  # which the host runs through caisson's `microvm-host` NixOS
  # module and the units of microvm.nix's host module
  # (tests/microvm-host-vm). The guest runs inside the test VM, so
  # it needs nested KVM. On a CI runner, which is itself a VM, the
  # guest is three levels deep and does not finish booting within
  # the start timeout, so the test is not a check; it is built by
  # name on a machine with KVM. The caisson top publishes it as its
  # `nestedVmTests` output.
  flake.nestedVmTests.x86_64-linux.microvm-host-vm =
    import (self.outPath + "/tests/microvm-host-vm")
      {
        inputs = inputs // {
          inherit caisson;
        };
      };
}
