# SPDX-License-Identifier: MIT
#
# This file is the function `mkVolatileCheck`. It returns the
# derivation of a check whose category is volatile: a check whose result
# depends on something outside the build, such as a service reached
# over the network.
#
# A configuration declares such a check with the derivation it returns:
#
#   caisson.checks.mirror-answers = {
#     category = "online";
#     derivation = lib.caisson.mkVolatileCheck {
#       inherit pkgs;
#       name = "mirror-answers";
#       program = pkgs.writeShellApplication {
#         name = "mirror-answers";
#         runtimeInputs = [ pkgs.curl ];
#         text = ''
#           curl --fail --silent --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
#             https://mirror.example.org/health
#         '';
#       };
#     };
#   };
#
# The derivation is a fixed-output derivation. Nix lets the builder of
# a fixed-output derivation reach the network, and in exchange the
# derivation declares the hash of its output in advance. The builder
# runs the program. When the program exits with status 0, the builder
# writes the pass marker, a file holding the line `pass`, as its
# output. When the program fails, the build fails and leaves nothing in
# the Nix store.
#
# Nix computes the store path of the output of a fixed-output
# derivation from its name and the declared hash alone. Every pass
# marker has the same hash, so the name tells markers apart: it is
# `<name>-<hash>`, where `<hash>` is the hash part of the store path of
# the program, the 32 characters after `/nix/store/`. A change to the
# program, or to anything its store path depends on, gives a new store
# path for the program and so a new marker. While the program stays the
# same, the marker path stays the same, and a marker already in the
# store, or in a cache, counts as a pass without the program running.
# A tool that runs the check again builds the marker with substitution
# off and `--rebuild`, as `topside check --rerun-volatile` does.
#
# Arguments:
#
# - `pkgs`: the package set for the system of the check. The builder
#   is the bash of this set, and the derivation is built for its host
#   platform.
# - `name`: the name of the check, the first part of the name of the
#   marker.
# - `program`: the executable the check runs, with no arguments. It is
#   a derivation whose output is an executable file, as
#   `pkgs.writeShellScript` returns, or a string naming an executable
#   inside a store path, as `lib.getExe` returns for
#   `pkgs.writeShellApplication`, or a path, which Nix copies into the
#   store. The builder sets no `PATH`, so the program reaches only the
#   commands it names by store path or puts on its `PATH` itself, as
#   `pkgs.writeShellApplication` does with its `runtimeInputs`. A
#   program that reaches a server over TLS names a CA bundle, such as
#   that of `pkgs.cacert`, since the build sandbox has none.
# - `impureEnvVars`: the names of the environment variables of the Nix
#   process that runs the build which Nix passes on to the builder.
#   With a Nix daemon, that process is the daemon. Of the machine that
#   builds the check, the program reaches the network and these
#   variables.
#
# The derivation is a plain `derivation`, so its `drvAttrs` hold the
# attributes above, and the store paths it depends on are the context
# of those attributes: the bash of `pkgs` and the program.
{
  pkgs,
  name,
  program,
  impureEnvVars ? [ ],
}:
let
  programPath = "${program}";
  storeHash = builtins.match "${builtins.storeDir}/([0-9a-z]{32})-.*" programPath;
in
if storeHash == null then
  throw ''
    caisson: mkVolatileCheck: the program of the check `${name}` is
    ${builtins.toJSON (builtins.unsafeDiscardStringContext programPath)}, which is not
    inside the Nix store. The name of the pass marker carries the hash of the store
    path of the program. Pass a derivation, a path, or a string inside a store path,
    such as `lib.getExe` of a package.
  ''
else
  derivation {
    name = "${name}-${builtins.head storeHash}";
    inherit (pkgs.stdenv.hostPlatform) system;
    builder = "${pkgs.bash}/bin/bash";
    args = [
      "-c"
      ''"$program" && printf 'pass\n' > "$out"''
    ];
    program = programPath;
    inherit impureEnvVars;
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = builtins.hashString "sha256" "pass\n";
  }
