# SPDX-License-Identifier: MIT
#
# hjem configurations declared through caisson's hjem integration, for
# the pinned-world suite and the hjem manifest check. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# tree itself.
#
# The composition is at x86_64-linux, with a package config whose set
# there is nixpkgs, and with nixpkgs and hjem declared as its
# ecosystems. `user` is an hjem module with a file and a package.
# `standalone` is an hjem configuration that is a top, for the user
# `probe` with the home directory it sets itself. `top` is a structural
# top holding a NixOS machine `probe-machine`, which declares the
# account of `probe` and an hjem configuration `probe` from
# `machineUser`, which is `user` with a systemd user unit.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    sources = { };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = {
      inherit (inputs) nixpkgs hjem;
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

  # The user inside the machine also declares a systemd user unit, which
  # only a user inside a NixOS machine can declare.
  machineUser = {
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

  machine = {
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
        caisson.nixos.configurations.probe-machine = lib.caisson.nixos.mkConfiguration {
          configModule =
            { lib, ... }:
            {
              imports = [ machine ];
              caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                configModule = machineUser;
              };
            };
        };
      };
  };
in
{
  inherit
    lib
    machine
    machineUser
    pkgs
    standalone
    system
    top
    user
    ;
  # The machine and the hjem configuration `probe` inside it, as their
  # manifests. Each evaluation of a configuration evaluated per system
  # sits under its system in the manifest of its parent.
  machineManifest = top.caisson.manifest.children.system.${system}.children.nixos.probe-machine;
  inner =
    top.caisson.manifest.children.system.${system}.children.nixos.probe-machine.children.system.${system}.children.hjem.probe;
}
