# SPDX-License-Identifier: MIT
#
# A NixOS test declared through the nixos-test integration, run in a
# VM: the check `test` that a structural caisson top
# gathers. `inputs` is the dependency pool of the checks partition with
# `caisson` set to the source of this repository.
#
# The NixOS configuration `nas-1` declares the test `smoke` and gives
# it no module, so the test takes the module registered under its name,
# configs/nixosTest/smoke. The node of the test writes the host name of
# `nas-1`, which the test reads from the result of the childless
# evaluation of `nas-1`, to a file, and the test script reads the file
# in the VM.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    name = "nixos-test-vm";
    dependencies = {
      inherit (inputs) nixpkgs;
    };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = dependencies: {
      nixpkgs-lib = dependencies.nixpkgs;
      nixos = dependencies.nixpkgs;
    };
    configs = lib: lib.caisson-core.mkModules ./configs;
    pkgSets = _lib: {
      default =
        { name, parent }:
        {
          _type = "caisson-manifest";
          type = "nixpkgs";
          inherit name parent;
          children.nixpkgs.${system} = {
            _type = "caisson-manifest";
            type = "nixpkgs";
            name = system;
            value = pkgs;
          };
        };
    };
  };

  top = lib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
          configModule =
            { lib, ... }:
            {
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              system.stateVersion = "25.05";
              networking.hostName = "nas-one";
              caisson.nixos-test.configurations.smoke = lib.caisson.nixos-test.mkConfiguration { };
            };
        };
      };
  };
in
top.checks.${system}.test
