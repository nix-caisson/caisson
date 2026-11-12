# SPDX-License-Identifier: MIT
#
# The structural caisson top of caisson: what a reader that indexes attributes of
# this file's value gets (`nix-build -A`, `nix eval -f`, a project
# reader): the exports of the structural configuration in
# configs/structural/caisson, with `caisson.manifest` beside them.
# flake.nix is the flake-parts caisson top over the same
# configuration.
#
# The pins are those in flake.lock, read without the flake evaluator
# by caisson-core's flake-compat reader, so this caisson top and the
# flake-parts caisson top build from the same source trees and a pin advance moves both. caisson-core
# itself is fetched from its node in the lock first, since the reader
# is one of its functions. The root is the working tree, named by its
# revision when clean (an impure read, as the read of a flakeless caisson top is).
let

  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  coreNode = lock.nodes.${lock.nodes.${lock.root}.inputs.caisson-core};

  core = import (builtins.fetchTree coreNode.locked);

  pins = import ./lib-overlays/framework/pins;

  lib = core.mkLib {
    inherit (pins.flake-compat ./.) dependencies;
    root = pins.gitRoot ./.;
    name = "caisson";
    systems = import ./systems.nix;
    modules = lib: lib.caisson-core.mkModules ./modules;
    configs = lib: lib.caisson-core.mkModules ./configs;
    libOverlays = lib: lib.caisson-core.mkLibOverlays ./lib-overlays;
  };

in
# The configuration registered under the name the composition
# declares, configs/structural/caisson.
lib.caisson.structural.mkTopConfiguration { }
