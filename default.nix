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
      rev = "97e941f303908484e213cf932916e3d76dc5b5e6";
      narHash = "sha256-iGMp70NBaFwolzIj9kU8NQ42FGnWWm9B/lYYCgViKoM=";
    };
    nixpkgs-lib = {
      type = "github";
      owner = "nix-community";
      repo = "nixpkgs.lib";
      rev = "b91d4f1bc958e0bdfd6cb3db4a280486006f5002";
      narHash = "sha256-XtTdVeJX6X/gU+vGIUEJHirotv/lYP5+Q9irMH6HWPY=";
    };
  };

  caisson-core = import (builtins.fetchTree pins.caisson-core);

  lib = caisson-core.mkLib {
    inputs = {
      nixpkgs-lib = builtins.fetchTree pins.nixpkgs-lib;
    };
    systems = import ./systems.nix;
    modules = import ./modules.nix;
    configs = import ./configs.nix;
    libOverlays = import ./libOverlays.nix;
  };

in
lib.caisson.structural.mkTopConfiguration {
  configModule = lib.caisson-core.configs.structural.caisson;
}
