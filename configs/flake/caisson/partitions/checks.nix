# SPDX-License-Identifier: MIT
{
  inputs,
  lib,
  self,
  ...
}:
{

  partitions.checks = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../../tests/dependencies).sources;
    module =
      { inputs, self, ... }:
      let
        # The inputs of the system-manager tests: the dependency pool
        # with `caisson` set to this tree.
        testInputs = inputs // {
          caisson = self;
        };
      in
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        systems = [ "x86_64-linux" ];
        perSystem =
          { system, ... }:
          let
            # Consumer-style flakes, evaluated from source with inputs
            # resolved by name from this pool (see callConsumerFlake).
            consumerPool = {
              inherit (inputs)
                flake-parts
                nixpkgs
                nixpkgs-lib
                nix-unit
                ;
              deps = inputs.self;
              parent = self;
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

            # A project that registers package overlays, and a consumer
            # that takes them through `projects`.
            pkgOverlaysProducerOutputs = callConsumer {
              path = self.outPath + "/tests/integration/pkg-overlays-registry/producer";
            };

            pkgOverlaysConsumerOutputs = callConsumer {
              path = self.outPath + "/tests/integration/pkg-overlays-registry/consumer";
              overrides.producer = pkgOverlaysProducerOutputs;
            };

            # Unit Tests
            unitTestOutputs = callConsumer {
              path = self.outPath + "/tests/unit";
            };

            # Example: Literate Flake
            exampleOutputs = callConsumer {
              path = self.outPath + "/examples/literate-flake";
              overrides.caisson = self;
            };

            pkgs = inputs.nixpkgs.legacyPackages.${system};

            # Imported directly (not via lib) because a partition's
            # inputs.self is the extra-inputs flake, not caisson itself.
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
                sources = { };
                defaultEcosystemSrc.nixpkgs-lib = ${inputs.nixpkgs-lib.outPath};
                modules = lib: lib.caisson-core.mkModules ${self.outPath}/modules;
                libOverlays = lib: lib.caisson-core.mkLibOverlays ${self.outPath}/lib-overlays;
              }
            '';

          in
          {
            # Duplicated in formatter.nix: partitions evaluate independently,
            # so sharing would require more boilerplate than the duplication.
            treefmt = {
              programs.nixfmt.enable = true;
            };
            checks =
              integrationOutputs.checks.${system}
              // minimalConsumerOutputs.checks.${system}
              // moduleClassExportOutputs.checks.${system}
              // libConsumerChainFinalOutputs.checks.${system}
              // nixpkgsConsumerOutputs.checks.${system}
              // nixpkgsOverlayExportOutputs.checks.${system}
              // nixpkgsNoPkgSetsOutputs.checks.${system}
              // nixpkgsPkgSetsOutputs.checks.${system}
              // pkgOverlaysProducerOutputs.checks.${system}
              // pkgOverlaysConsumerOutputs.checks.${system}
              // unitTestOutputs.checks.${system}
              // {
                literate-flake-default = exampleOutputs.packages.${system}.default;
                literate-flake-greeting = exampleOutputs.packages.${system}.greeting;
                debug-disabled =
                  assert !(self ? debug);
                  pkgs.runCommand "debug-disabled" { } "touch $out";
                # The pinned-world suite, forced at evaluation time: the
                # tree itself composed with the upstream pins of
                # tests/dependencies, so the check evaluates caisson
                # against the committed world. The drift workflow builds
                # this check alone over advanced pins.
                pinned-world =
                  let
                    suite = import (self.outPath + "/tests/pinned-world") {
                      inputs = inputs // {
                        caisson = self;
                      };
                    };
                  in
                  builtins.seq suite.summary (pkgs.runCommand "pinned-world" { } "touch $out");
                # The manifest file of a hjem configuration inside a NixOS
                # machine and the units that activate it, built. Building
                # the manifest file checks it against hjem's own schema
                # with `cue vet`, so the file the machine activates is one
                # hjem's CLI accepts. Building the units runs shellcheck
                # on their scripts.
                hjem-system =
                  let
                    probe = import (self.outPath + "/tests/hjem-system") {
                      inputs = inputs // {
                        caisson = self;
                      };
                    };
                    units = probe.top.nixosConfigurations.probe-machine.config.systemd.units;
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
                    caisson = self;
                  };
                };
                # A machine booted in a VM that activates the homes, the
                # hjem configurations and the profiles declared inside
                # it, and a standalone hjem configuration, each through
                # sequences of changes (tests/activation-vm).
                activation-vm = import (self.outPath + "/tests/activation-vm") {
                  inputs = inputs // {
                    caisson = self;
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
                    # one instantiation of flake-parts' library over the
                    # composed lib, since the raw scenario's flake-parts is
                    # built over the plain nixpkgs lib and is not shared,
                    # and the evaluation of the structural configuration
                    # caisson's flake top holds beneath it, which reading
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
              };
          };

        # A system-manager machine activated in a container of each
        # distribution of tests/system-manager/container-distros.nix,
        # through sequences of changes, as
        # `system-manager-<distribution>`. The container runs in the
        # build sandbox only where Nix runs with
        # `auto-allocate-uids = true`, so the tests are not checks
        # `nix flake check` builds; the workflow builds them by name.
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

        # The same machine and sequences in a VM of each distribution
        # below, booted from the cloud image of the distribution with
        # its kernel and its systemd, as
        # `system-manager-vm-<distribution>`. The systemd of these
        # distributions needs a VM to start logind and the other services
        # the distribution ships with.
        flake.checks.x86_64-linux = builtins.listToAttrs (
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

        # A macOS machine declared through the darwin integration, built:
        # the system `darwin-rebuild` would build for it. It is the only
        # check for aarch64-darwin. The pinned-world suite evaluates the
        # same machine on any host; building it needs a darwin builder,
        # so the darwin job of the workflow builds it on a macOS runner.
        flake.checks.aarch64-darwin.darwin-system =
          let
            probe = import (self.outPath + "/tests/darwin-system") {
              inputs = inputs // {
                caisson = self;
              };
            };
          in
          # The bare machine, and the machine with a home and a hjem
          # configuration inside it, whose system holds the activation
          # of the home and the launchd agents of hjem. Beside them, the
          # manifests of a hjem configuration that is a top, in the
          # versions v1 and v2, and the hjem CLI, with which the darwin job applies
          # it on the runner (tests/darwin-system/hjem-standalone.sh).
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
            # The machine for the runner in each version, which the
            # darwin job activates on the runner
            # (tests/darwin-system/runner-machine.sh).
            {
              name = "runner-machine/v1";
              path = (probe.runnerMachineOf "v1").darwinConfigurations.runner-machine.system;
            }
            {
              name = "runner-machine/v2";
              path = (probe.runnerMachineOf "v2").darwinConfigurations.runner-machine.system;
            }
            # The activation package of the home of `runner` in each
            # version, which the script runs by hand.
            {
              name = "runner-machine/home-v1";
              path = (probe.runnerMachineOf "v1").homeConfigurations."runner@runner-machine".activationPackage;
            }
            {
              name = "runner-machine/home-v2";
              path = (probe.runnerMachineOf "v2").homeConfigurations."runner@runner-machine".activationPackage;
            }
          ];
      };
  };

}
