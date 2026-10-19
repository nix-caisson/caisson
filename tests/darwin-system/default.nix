# SPDX-License-Identifier: MIT
#
# A macOS machine declared through caisson's darwin integration, for
# the pinned-world suite and the darwin build check. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# tree itself.
#
# The composition is for aarch64-darwin, with a package config whose set
# there is nixpkgs for aarch64-darwin, and with nixpkgs, nix-darwin,
# home-manager, hjem and nvf declared as its ecosystems. A structural top declares the machine
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
        nvf
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

  # A hjem configuration that is a top, applied with
  # `hjem standalone switch`, with the nvf configuration
  # `standalone-editor` inside it, in a version: the Neovim of v2 also
  # has `vim`. It is for the user `runner`, the user of the macOS runner
  # of the workflow, which applies it there.
  standaloneHjemOf =
    version:
    (lib.caisson.hjem.mkTopConfiguration {
      configModule =
        { lib, ... }:
        {
          user = "runner";
          directory = "/Users/runner";
          caisson.nvf.configurations.standalone-editor = lib.caisson.nvf.mkConfiguration {
            configModule.vim = {
              viAlias = true;
              vimAlias = version == "v2";
            };
          };
        };
    }).caisson.manifest;
  standaloneHjem = standaloneHjemOf "v1";

  # A top holding a macOS machine for the runner of the workflow, which
  # activates it there, in a version. The machine declares the nvf
  # configuration `editor`, a profile of the system, a home for
  # `runner`, the account of the runner, and a hjem configuration for
  # `runner` with the nvf configuration `hjem-editor` inside it. A file
  # of the machine, of the home and of the hjem configuration each names
  # the version, and the Neovims of v2 also have `vim`. nix-darwin manages neither Nix nor zsh here, so
  # activating the machine leaves the Nix and the `/etc/zshrc` of the
  # runner as they are.
  runnerMachineOf =
    version:
    let
      editor = {
        vim.viAlias = true;
        vim.vimAlias = version == "v2";
      };
    in
    (lib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.darwin.configurations.runner-machine = lib.caisson.darwin.mkConfiguration {
            configModule =
              { lib, ... }:
              {
                system.stateVersion = 6;
                system.primaryUser = "runner";
                nix.enable = false;
                programs.zsh.enable = false;
                users.users.runner = {
                  home = "/Users/runner";
                  uid = 501;
                };
                # A file of the machine itself, so that the machine
                # without the configurations declared inside it, which
                # the home checks for drift, differs between the
                # versions.
                environment.etc."probe/version".text = version;
                caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
                  configModule = editor;
                };
                caisson.home-manager.configurations.runner = lib.caisson.home-manager.mkConfiguration {
                  configModule = {
                    home.stateVersion = "25.05";
                    home.file.".config/probe/hm-version".text = version;
                  };
                };
                caisson.hjem.configurations.runner = lib.caisson.hjem.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      files.".config/probe/version".text = version;
                      caisson.nvf.configurations.hjem-editor = lib.caisson.nvf.mkConfiguration {
                        configModule = editor;
                      };
                    };
                };
              };
          };
        };
    });

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
    runnerMachineOf
    standaloneHjem
    standaloneHjemOf
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
