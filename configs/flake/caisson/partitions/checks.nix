# SPDX-License-Identifier: MIT
{
  inputs,
  lib,
  self,
  ...
}:
{

  partitions.checks = {
    extraInputs = (lib.caisson-core.pins.flake-compat ../../../../tests/dependencies).sources;
    module =
      { inputs, self, ... }:
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
              lib.caisson-core.callConsumerFlake (
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
                modules = core.mkModules ${self.outPath}/modules;
                libOverlays = core.mkLibOverlays ${self.outPath}/lib-overlays;
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
      };
  };

}
