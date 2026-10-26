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
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-topology.url = "github:oddlama/nix-topology";
  inputs.nix-topology.inputs.nixpkgs.follows = "nixpkgs";
  inputs.kubenix.url = "github:hall/kubenix";
  inputs.kubenix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixidy.url = "github:arnarg/nixidy";
  inputs.nixidy.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixvim.url = "github:nix-community/nixvim";
  inputs.nixvim.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nvf.url = "github:NotAShelf/nvf";
  inputs.nvf.inputs.nixpkgs.follows = "nixpkgs";
  inputs.hjem.url = "github:feel-co/hjem";
  inputs.hjem.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-darwin.url = "github:nix-darwin/nix-darwin";
  inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  inputs.microvm.url = "github:microvm-nix/microvm.nix";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixops4.url = "github:nixops4/nixops4";
  inputs.nixops4.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixops4.inputs.flake-parts.follows = "flake-parts";
  inputs.nixops4-nixos.url = "github:nixops4/nixops4-nixos";
  inputs.nixops4-nixos.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixops4-nixos.inputs.flake-parts.follows = "flake-parts";
  # The VMs of other distributions the system-manager VM test boots
  # (tests/system-manager).
  inputs.nix-vm-test.url = "github:numtide/nix-vm-test";
  inputs.nix-vm-test.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { ... }: { };
}
