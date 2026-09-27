# SPDX-License-Identifier: MIT
{
  inputs.caisson-core.url = "github:nix-caisson/caisson-core";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  inputs.nix-unit.url = "github:nix-community/nix-unit";
  inputs.nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  # The upstream world the pinned-world suite (tests/pinned-world)
  # evaluates against.
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.colmena.url = "github:zhaofengli/colmena";
  inputs.colmena.inputs.nixpkgs.follows = "nixpkgs";
  inputs.terranix.url = "github:terranix/terranix";
  inputs.terranix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.system-manager.url = "github:numtide/system-manager";
  inputs.system-manager.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { ... }: { };
}
