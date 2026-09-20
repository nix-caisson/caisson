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
      rev = "cf7317cb03067c1cc12735985c7124ec6ebce1d8";
      narHash = "sha256-DAkrrGVfFtQqDn0CFt0oNrMKYhLxq4lYvLhfqMUUN+8=";
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

  lib = import ./composition/lib.nix {
    inherit caisson-core;
    inputs = {
      nixpkgs-lib = builtins.fetchTree pins.nixpkgs-lib;
    };
  };

in
lib.caisson.structural.mkTopConfiguration {
  configModule = lib.caisson.structural.mkModule ./configs/structural/caisson;
}
