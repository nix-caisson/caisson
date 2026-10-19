# SPDX-License-Identifier: MIT
#
# A macOS machine declared through caisson's darwin integration, for
# the pinned-world suite and the darwin build check. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# tree itself.
#
# The composition is for aarch64-darwin, with a package config whose set
# there is nixpkgs for aarch64-darwin, and with nixpkgs, nix-darwin,
# home-manager and hjem declared as its ecosystems. A structural top declares the machine
# `probe` from `machine`, and the machine `family`, which is `machine`
# with a home and a hjem configuration for the user `probe` declared
# inside it. Evaluating them needs no Mac: the package set
# and the derivations are evaluated for aarch64-darwin wherever the
# evaluation runs. Building the system needs a darwin builder.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "aarch64-darwin";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    sources = { };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = {
      inherit (inputs)
        nixpkgs
        nix-darwin
        home-manager
        hjem
        ;
    };
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

  # The machine: a user, a package and a launchd daemon, so the system
  # has the parts darwin-rebuild activates.
  machine = {
    system.stateVersion = 6;
    system.primaryUser = "probe";
    users.users.probe = {
      home = "/Users/probe";
      uid = 501;
    };
    environment.systemPackages = [ pkgs.hello ];
    launchd.daemons.caisson-probe.serviceConfig = {
      ProgramArguments = [
        "/bin/echo"
        "caisson"
      ];
      RunAtLoad = true;
    };
  };

  # A home and a hjem configuration for the user `probe`.
  home = {
    home.stateVersion = "25.05";
    home.file.".probe".text = "home";
  };
  hjemUser = {
    files.".config/probe/greeting".text = "hjem";
    packages = [ pkgs.hello ];
  };

  top = lib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.darwin.configurations.probe = lib.caisson.darwin.mkConfiguration {
          configModule = machine;
        };
        # The same machine, with the home and the hjem configuration of
        # `probe` declared inside it.
        caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
          configModule =
            { lib, ... }:
            {
              imports = [ machine ];
              caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration {
                configModule = home;
              };
              caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                configModule = hjemUser;
              };
            };
        };
      };
  };
in
{
  inherit
    hjemUser
    home
    lib
    machine
    pkgs
    system
    top
    ;
  # The machine as darwin-rebuild reads it, and the system it builds.
  configuration = top.darwinConfigurations.probe;
  toplevel = top.darwinConfigurations.probe.system;
  # The machine with the home and the hjem configuration, and the
  # manifests of the two inside it.
  family = top.darwinConfigurations.family;
  familyManifest = top.caisson.manifest.children.system.${system}.children.darwin.family;
}
