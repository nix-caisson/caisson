# SPDX-License-Identifier: MIT
#
# This file is the function `realizeInputs`. The function takes flake
# inputs that Nix has already resolved. It makes sure that each input
# is present in the Nix store, and it returns the store path of each
# input. It does the same for the inputs of each input, and for the
# inputs of those, to any depth. "Realize" is the word Nix uses for
# making sure a store path is present: `nix-store --realise`. The
# function uses builtins only.
#
# The problem the function solves
#
# Some tools evaluate a flake from inside a Nix build. nix-unit does
# this when it runs as a flake check. The check is a derivation. The
# builder of that derivation runs nix-unit, and nix-unit evaluates
# the flake that holds the tests.
#
# Nix runs every builder in a sandbox. Inside the sandbox, the
# builder can see a path in the Nix store only when the derivation
# names that path as a dependency. The rest of the store is hidden
# from the builder. The builder also has no network access.
#
# So when nix-unit evaluates the flake and the evaluation needs a
# flake input, two things go wrong. Nix looks for the input in the
# store and does not see it, because the derivation did not name it.
# Nix then tries to download the input and cannot, because the
# builder has no network access. The check fails with the message
# "unable to download".
#
# The lock file of the flake does not change this. The lock file
# tells Nix which revision of the input to use. It does not put a
# copy of that revision where the builder can see it.
#
# How the problem is solved by hand
#
# nix-unit accepts the flag `--override-input <name> <store path>`
# for each input. The flag does two things. It tells nix-unit to read
# the input from that store path and not to fetch it. And the store
# path is now written in the command that the builder runs, so the
# derivation names the store path as a dependency, and the builder
# can see it. The flake-parts module of nix-unit writes these flags
# from the option `nix-unit.inputs`, which is an attribute set of
# names and store paths.
#
# The inputs of an input need the same flag. Suppose a test composes
# caisson as a project. To do that, nix-unit has to evaluate the
# caisson flake. The caisson flake has inputs too, and caisson-core
# is one of them. Nix looks for caisson-core, does not see it, and
# the check fails in the way described above. The flag for an input
# of an input names both of them:
# `--override-input caisson/caisson-core <store path>`.
#
# Writing these flags by hand means copying the list of inputs out
# of the lock file of the caisson flake, and keeping that copy up to
# date. If a name is missing from the copy, nothing reports it until
# the check runs and fails inside the sandbox.
#
# What the function returns
#
# The function builds the whole set of names and store paths from
# the resolved inputs. The name of each input is the list of input
# names that leads to it, joined with `/`. That is the form of name
# that `--override-input` takes:
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
# When two inputs both follow a third input, the third input appears
# in the result twice, once under each name that leads to it.
#
# Which inputs to give the function
#
# To return the store path of an input, Nix has to fetch that input.
# The function therefore fetches every input it is given, and every
# input of those inputs, to any depth. It fetches an input even when
# no test reads it.
#
# For that reason, give the function only the inputs that the tests
# evaluate as flakes. List the other inputs of the test flake
# directly:
#
#   nix-unit.inputs = inputs // lib.caisson.realizeInputs { inherit (inputs) caisson; };
#
# In this line, `inputs` gives nix-unit each input of the test flake
# under its name. The call to `realizeInputs` adds the inputs of the
# caisson flake.
#
# Do not give the function all of `inputs`. It would then also fetch
# the inputs of nix-unit, the inputs of nixpkgs, and the inputs of
# every other input of the test flake. Most of those are inputs that
# no test reads.
let

  # `pathOf` returns the store path of an input. Nix puts the store
  # path of an input in its `outPath` attribute. That is true of an
  # input that is a flake and of an input that is a plain source tree.
  # A caller may also write the store path directly as the value, so
  # a value without an `outPath` is taken to be the store path.
  pathOf = input: input.outPath or input;

  # `inputsOf` returns the inputs of an input. Nix puts them in the
  # `inputs` attribute of an input that is a flake. An input that is
  # a plain source tree (`flake = false`) has no `inputs` attribute,
  # and a store path written directly is not an attribute set. Both
  # have no inputs.
  inputsOf = input: if builtins.isAttrs input then input.inputs or { } else { };

  # `namesOf` returns the names of the inputs to list. It leaves out
  # `self`. In the inputs of a flake, `self` is that flake itself and
  # not something the flake depends on. A tool such as nix-unit is
  # told which flake to evaluate separately, so `self` needs no flag.
  namesOf = inputs: builtins.filter (name: name != "self") (builtins.attrNames inputs);

  # `under prefix inputs` returns the result for `inputs`, with
  # `prefix` written in front of each name. The function calls itself
  # on the inputs of each input, with the name of that input and a
  # `/` added to the prefix.
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
