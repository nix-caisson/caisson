# SPDX-License-Identifier: MIT
#
# A NixOS test of the profiles a machine activates, run in a VM.
# `inputs` is the dependency pool of the checks partition with
# `caisson` set to the tree itself.
#
# A NixOS configuration declares the nvf configuration `editor` inside
# it, so the machine keeps the Neovim of `editor` in the profile of the
# system `/nix/var/nix/profiles/caisson/nvf/editor`, and the unit
# `caisson-profile-nvf-editor` activates the profile. The test checks
# that the unit has activated the profile once the machine has booted,
# that the `nvim` of the machine runs the Neovim of the profile, and
# that a profile changed by hand is put back to the declared Neovim
# when the machine boots again.
#
# The NixOS test framework evaluates its nodes itself, with the
# `eval-config.nix` of nixpkgs, and a node is a NixOS module. The node
# here is evaluated on the library of a caisson evaluation of the same
# machine, passed through `node.specialArgs`, so the modules of caisson
# find `lib.caisson` and the manifest of the machine. The node imports
# what caisson's NixOS evaluator imports from the registry: the
# framework modules of the class and caisson's `default` module.
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
      inherit (inputs) nixpkgs nvf;
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

  # The machine: the nvf configuration `editor` declared inside it.
  machine =
    { lib, ... }:
    {
      caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
        configModule.vim.viAlias = true;
      };
    };

  # The library of the caisson evaluation of the machine, which carries
  # the manifest of that evaluation. A module of the evaluation hands
  # the library out through an option.
  machineLib =
    (lib.caisson.nixos.mkTopConfiguration {
      configModule =
        { lib, ... }:
        {
          imports = [ machine ];
          options.profileVmLib = lib.mkOption { type = lib.types.raw; };
          config = {
            profileVmLib = lib;
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.05";
          };
        };
    }).config.profileVmLib;

  registry = machineLib.caisson.modules.nixos;

  profile = "/nix/var/nix/profiles/caisson/nvf/editor";
in
pkgs.testers.runNixOSTest {
  name = "caisson-profile-vm";

  node.specialArgs.lib = machineLib;

  nodes.machine = {
    imports = machineLib.caisson.integrations.frameworkModules "nixos" registry ++ [
      registry."caisson/default"
      machine
    ];
    system.stateVersion = "25.05";
  };

  testScript = ''
    machine.wait_for_unit("caisson-profile-nvf-editor.service")

    # The unit has activated the profile, and the `nvim` of the machine
    # runs the Neovim of the profile.
    machine.succeed("test -x ${profile}/bin/nvim")
    machine.succeed("test -x ${profile}/bin/vi")
    declared = machine.succeed("readlink -f ${profile}").strip()
    machine.succeed("nvim --headless +qa")

    # A profile changed by hand is put back when the machine boots. The
    # profile is set to the system of the machine, which has no `nvim`.
    machine.succeed("nix-env --profile ${profile} --set $(readlink -f /run/current-system)")
    machine.fail("test -e ${profile}/bin/nvim")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("caisson-profile-nvf-editor.service")
    restored = machine.succeed("readlink -f ${profile}").strip()
    assert restored == declared, f"the profile is {restored}, not {declared}"
    machine.succeed("test -x ${profile}/bin/nvim")
  '';
}
