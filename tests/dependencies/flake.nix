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
  outputs = { ... }: { };
}
