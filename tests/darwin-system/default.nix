# SPDX-License-Identifier: MIT
#
# A nix-darwin configuration declared through caisson's darwin
# integration, for the pinned-world suite and the darwin build check. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# source of this repository.
#
# The composition is for aarch64-darwin, with a package config whose set
# there is nixpkgs for aarch64-darwin, and with nixpkgs, nix-darwin,
# home-manager, hjem and nvf declared as its ecosystems. A structural
# caisson top declares the nix-darwin configuration `probe` from `baseModule`,
# and the nix-darwin configuration `family`, which is `baseModule` with
# a home-manager configuration and a hjem configuration for the user
# `probe` declared inside it. Evaluating them needs no Mac: the package
# set and the derivations are evaluated for aarch64-darwin on whatever
# computer runs the evaluation. Building
# the system needs a darwin builder.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "aarch64-darwin";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    dependencies = {
      inherit (inputs)
        nixpkgs
        nix-darwin
        home-manager
        hjem
        nvf
        ;
    };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = dependencies: { nixpkgs-lib = dependencies.nixpkgs; };
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

  # The module of the nix-darwin configuration: a user, a package and a
  # launchd daemon, so the system has the parts darwin-rebuild activates.
  baseModule = {
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

  # A home-manager configuration and a hjem configuration for the user
  # `probe`.
  homeManagerModule = {
    home.stateVersion = "25.05";
    home.file.".probe".text = "home";
  };
  hjemUser = {
    files.".config/probe/greeting".text = "hjem";
    packages = [ pkgs.hello ];
  };

  # A hjem configuration that is a caisson top, applied with
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

  # A caisson top holding a nix-darwin configuration for the runner of the
  # workflow, which activates it there, in a version. The nix-darwin
  # configuration declares the nvf configuration `editor`, a profile of
  # the system, a home-manager configuration for `runner`, the account
  # of the runner, and a hjem configuration for `runner` with the nvf
  # configuration `hjem-editor` inside it. A file of the nix-darwin
  # configuration, of the home-manager configuration and of the hjem
  # configuration each names the version, and the Neovims of v2 also
  # have `vim`. nix-darwin manages neither Nix nor zsh here, so
  # activating the nix-darwin configuration leaves the Nix and the
  # `/etc/zshrc` of the runner as they are.
  runnerDarwinOf =
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
          caisson.darwin.configurations.runner-darwin = lib.caisson.darwin.mkConfiguration {
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
                # A file of the nix-darwin configuration itself, so
                # that the result of its childless evaluation, which the
                # home-manager configuration checks for drift, differs
                # between the versions.
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
          configModule = baseModule;
        };
        # The same module, with the home-manager configuration and the
        # hjem configuration of `probe` declared inside it.
        caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
          configModule =
            { lib, ... }:
            {
              imports = [ baseModule ];
              caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration {
                configModule = homeManagerModule;
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
    baseModule
    hjemUser
    homeManagerModule
    lib
    pkgs
    runnerDarwinOf
    standaloneHjem
    standaloneHjemOf
    system
    top
    ;
  # The nix-darwin configuration as darwin-rebuild reads it, and the
  # system it builds.
  configuration = top.darwinConfigurations.probe;
  toplevel = top.darwinConfigurations.probe.system;
  # The nix-darwin configuration with the home-manager configuration and
  # the hjem configuration, and its manifest.
  family = top.darwinConfigurations.family;
  familyManifest = top.caisson.manifest.children.system.${system}.children.darwin.family;
}
