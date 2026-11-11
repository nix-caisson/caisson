# SPDX-License-Identifier: MIT
#
# hjem configurations declared through caisson's hjem integration, for
# the pinned-world suite and the hjem manifest check. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# source of this repository.
#
# The composition is for x86_64-linux, with a package config whose set
# there is nixpkgs, and with nixpkgs, hjem, the library and the NixOS
# module collection declared as its ecosystems, the library and the
# module collection from the same nixpkgs pin. `user` is a hjem module
# with a file and a package.
# `standalone` is a hjem configuration that is a top, for the user
# `probe` with the home directory it sets itself. `top` is a structural
# top holding a NixOS configuration `probe-nixos` from `baseModule`,
# which declares the account of `probe`, and a hjem configuration
# `probe` from `unitUser`, which is `user` with a systemd user unit.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    dependencies = {
      inherit (inputs)
        nixpkgs
        hjem
        nvf
        home-manager
        ;
    };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = dependencies: {
      nixpkgs-lib = dependencies.nixpkgs;
      nixos = dependencies.nixpkgs;
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

  user = {
    files.".config/probe/greeting".text = "hello from caisson";
    xdg.config.files."probe/settings".source = pkgs.writeText "settings" "probe";
    packages = [ pkgs.hello ];
  };

  # The user inside the NixOS configuration also declares a systemd user
  # unit, which only a hjem configuration inside a NixOS configuration
  # can declare.
  unitUser = {
    imports = [ user ];
    systemd.services.probe = {
      description = "probe";
      script = "true";
      wantedBy = [ "default.target" ];
    };
  };

  standalone = lib.caisson.hjem.mkTopConfiguration {
    configModule = {
      imports = [ user ];
      user = "probe";
      directory = "/home/probe";
    };
  };

  # The module of the NixOS configuration.
  baseModule = {
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "25.05";
    users.users.probe = {
      isNormalUser = true;
      home = "/home/probe";
    };
  };

  top = lib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.probe-nixos = lib.caisson.nixos.mkConfiguration {
          configModule =
            { lib, ... }:
            {
              imports = [ baseModule ];
              caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                configModule = unitUser;
              };
            };
        };
      };
  };
in
{
  inherit
    baseModule
    lib
    pkgs
    standalone
    system
    top
    unitUser
    user
    ;
  # The NixOS configuration and the hjem configuration `probe` inside
  # it, as their manifests. Each evaluation result of a configuration
  # evaluated per system sits under its system in the manifest of its
  # parent.
  nixosManifest = top.caisson.manifest.children.system.${system}.children.nixos.probe-nixos;
  inner =
    top.caisson.manifest.children.system.${system}.children.nixos.probe-nixos.children.system.${system}.children.hjem.probe;
}
