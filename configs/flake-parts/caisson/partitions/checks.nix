# SPDX-License-Identifier: MIT
{
  inputs,
  lib,
  self,
  ...
}:
{

  partitions.checks = {
    extraInputs = lib.caisson-core.partitionExtraInputs ../../../../tests/dependencies;
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
              // unitTestOutputs.checks.${system}
              // {
                literate-flake-default = exampleOutputs.packages.${system}.default;
                literate-flake-greeting = exampleOutputs.packages.${system}.greeting;
                debug-disabled =
                  assert !(self ? debug);
                  pkgs.runCommand "debug-disabled" { } "touch $out";
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
                    # The framework's own cost, isolated from flake-parts +
                    # nixpkgs churn: this is the number that must not creep.
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
