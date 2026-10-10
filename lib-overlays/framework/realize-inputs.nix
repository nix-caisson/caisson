# SPDX-License-Identifier: MIT
#
# Realize resolved flake inputs, in the sense of `nix-store --realise`:
# make sure each is in the store, and return the store path of each.
# The inputs of an input are realized too, to any depth. This file is
# the function itself; it uses builtins only.
#
# The function exists for tools that evaluate a flake from inside a
# Nix build. nix-unit is such a tool when it runs as a flake check.
# The check is a derivation, and its builder runs nix-unit on the
# flake that holds the tests.
#
# A builder runs in a sandbox. It can read only the store paths that
# are inputs of its derivation, and it has no network. So when the
# evaluation inside the builder comes to a flake input, Nix can
# neither find it in the store nor download it, and the check fails
# with "unable to download". The lock file does not help. It says
# which revision the input is, and the sandbox still has no copy of
# that revision and no way to fetch one.
#
# The way out is to pass each input to the tool as
# `--override-input <name> <store path>`. The tool then reads the
# input from that store path, and the store path becomes an input of
# the derivation, so the sandbox can read it. For nix-unit, the
# `nix-unit.inputs` option takes these as an attribute set.
#
# An input that the tests use as a flake has inputs too. A test that
# composes caisson as a project evaluates the caisson flake, which
# reads caisson-core from the lock file of caisson. That input needs
# an override as well, under the name `caisson/caisson-core`.
# Writing those by hand means repeating the lock file of every such
# flake, and a missing name fails only inside the sandbox.
#
# This function produces the whole set from the inputs Nix has
# already resolved. Each input is named by the path of input names
# that leads to it, which is the name `--override-input` takes:
#
#   realizeInputs { inherit caisson; }
#   => {
#     "caisson" = "/nix/store/…-source";
#     "caisson/caisson-core" = "/nix/store/…-source";
#     "caisson/flake-parts" = "/nix/store/…-source";
#     "caisson/flake-parts/nixpkgs-lib" = "/nix/store/…-source";
#     "caisson/nixpkgs-lib" = "/nix/store/…-source";
#   }
#
# An input that several others follow is listed once for each path
# to it.
#
# Realizing an input fetches it, so the function fetches every input
# in the tree it is given, whether a test reads it or not. Give it
# the inputs that the tests use as flakes, and list the other inputs
# of the test flake directly:
#
#   nix-unit.inputs = inputs // lib.caisson.realizeInputs { inherit (inputs) caisson; };
#
# Here `inputs` covers every input of the test flake by name, and
# the function adds the inputs that caisson pins. Giving the function
# `inputs` itself would also fetch what nix-unit, nixpkgs and every
# other input pin, most of which no test reads.
let

  # The store path of a resolved input. Nix gives a flake input and a
  # source tree alike an `outPath`; a value written by hand may be the
  # path itself.
  pathOf = input: input.outPath or input;

  # The inputs a resolved input has. A source tree (`flake = false`)
  # has none, and neither has a bare path.
  inputsOf = input: if builtins.isAttrs input then input.inputs or { } else { };

  # `self` is the flake whose inputs these are. A tool is pointed at
  # that flake to evaluate it, so it is not one of the inputs to pass.
  namesOf = inputs: builtins.filter (name: name != "self") (builtins.attrNames inputs);

  # The realized inputs under `inputs`, each name prefixed with
  # `prefix`.
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
