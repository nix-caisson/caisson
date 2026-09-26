# SPDX-License-Identifier: MIT
#
# caisson's structural top: what a reader that indexes attributes of
# this file's value gets (`nix-build -A`, `nix eval -f`, a project
# reader): the exports of the structural configuration in
# configs/structural/caisson, with `caisson.manifest` beside them.
# flake.nix is the flake top over the same configuration.
#
# The two trees the composition needs are fetched from the pins below.
# They are this top's pins, in step with flake.lock; moving them is a
# pin advance like any other.
let

  pins = {
    caisson-core = {
      type = "github";
      owner = "nix-caisson";
      repo = "caisson-core";
      rev = "c677e69f34a354c7617aaf315165afa3d8cdb137";
      narHash = "sha256-IL8uY8ShiAPthlO9+CKNpbO1DO9DDaXyNXI5YjyoOkU=";
    };
    nixpkgs-lib = {
      type = "github";
      owner = "nix-community";
      repo = "nixpkgs.lib";
      rev = "b91d4f1bc958e0bdfd6cb3db4a280486006f5002";
      narHash = "sha256-XtTdVeJX6X/gU+vGIUEJHirotv/lYP5+Q9irMH6HWPY=";
    };
  };

  core = import (builtins.fetchTree pins.caisson-core);

  lib = core.mkLib {
    inputs = {
      nixpkgs-lib = builtins.fetchTree pins.nixpkgs-lib;
    };
    namespace = "caisson";
    systems = import ./systems.nix;
    modules = core.mkModules ./modules;
    configs = core.mkModules ./configs;
    libOverlays = core.mkLibOverlays ./lib-overlays;
  };

in
lib.caisson.structural.mkTopConfiguration {
  configModule = lib.caisson-core.configs.structural.caisson;
}
