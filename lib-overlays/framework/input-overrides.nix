# SPDX-License-Identifier: MIT
#
# The resolved inputs of a flake as a set of input overrides: what a
# second evaluation of that flake has to be handed so that it fetches
# nothing. This file is the function itself; it uses builtins only.
#
# Nix evaluates a flake against the store it can see. A command that
# evaluates the flake again inside a build (nix-unit run as a check
# does) sees only the store paths the build was handed and has no
# network, so an input is found only if it was handed over, although
# the lock records its hash. That holds for the inputs of an input
# too: when the second evaluation evaluates an input as a flake, it
# reads the inputs that flake pins.
#
# `--override-input` names an input of an input by the path of names
# to it, `caisson/caisson-core`. The result here has that shape:
#
#   inputOverrides { inherit caisson; }
#   => {
#     "caisson" = "/nix/store/…-source";
#     "caisson/caisson-core" = "/nix/store/…-source";
#     "caisson/flake-parts" = "/nix/store/…-source";
#     "caisson/flake-parts/nixpkgs-lib" = "/nix/store/…-source";
#     "caisson/nixpkgs-lib" = "/nix/store/…-source";
#   }
#
# Each override is a store path, so every input in the tree is
# fetched to produce the result. Pass the inputs the second
# evaluation evaluates as flakes, and hand over the rest as they are:
#
#   nix-unit.inputs = inputs // lib.caisson.inputOverrides { inherit (inputs) caisson; };
#
# Passing all the inputs of a flake fetches every input any of them
# pins, used or not.
let

  # The store path of a resolved input. Nix gives a flake input and a
  # source tree alike an `outPath`; a value written by hand may be the
  # path itself.
  pathOf = input: input.outPath or input;

  # The inputs a resolved input has. A source tree (`flake = false`)
  # has none, and neither has a bare path.
  inputsOf = input: if builtins.isAttrs input then input.inputs or { } else { };

  # `self` is the flake being evaluated, which the second evaluation
  # is given as the flake to evaluate and not as an input.
  namesOf = inputs: builtins.filter (name: name != "self") (builtins.attrNames inputs);

  # The overrides for `inputs`, each name prefixed with `prefix`.
  under =
    prefix: inputs:
    builtins.foldl' (
      acc: name:
      let
        input = inputs.${name};
        path = "${prefix}${name}";
      in
      acc // { ${path} = pathOf input; } // under "${path}/" (inputsOf input)
    ) { } (namesOf inputs);

in
inputs: under "" inputs
