# SPDX-License-Identifier: MIT
#
# A NixOS test of the profiles a machine activates, run in a VM.
# `inputs` is the dependency pool of the checks partition with
# `caisson` set to the tree itself.
#
# The machine declares the nvf configuration `editor` inside it, so it
# keeps the Neovim of `editor` in the profile of the system
# `/nix/var/nix/profiles/caisson/nvf/editor`, which the unit
# `caisson-profile-nvf-editor` activates. The test checks that the unit
# has activated the profile once the machine has booted, that the
# `nvim` of the machine runs the Neovim of the profile, and that a
# profile changed by hand is put back to the declared Neovim when the
# machine boots again.
#
# The machine also declares a hjem configuration for the user `alice`,
# with the nvf configuration `hjem-editor` inside it. The unit
# `caisson-profile-alice-nvf-hjem-editor` activates its profile in the
# home directory of `alice` whenever the machine applies the files of
# `alice`. The test checks that a switch puts the profile back after it
# is changed by hand.
#
# The user `bob` has a hjem configuration that is a top, with the nvf
# configuration `standalone-editor` inside it, applied with
# `hjem standalone switch`, as on a machine that caisson does not
# manage. The test applies it, starts the systemd of `bob` again, as a
# login does, and checks that the units in the files of `bob` have
# activated the profile. It then checks that the next
# `hjem standalone switch` puts the profile back after it is changed by
# hand.
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
      inherit (inputs) nixpkgs nvf hjem;
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

  # The hjem configuration of `bob`, applied with
  # `hjem standalone switch`, and its manifest as the file the CLI
  # reads.
  bob =
    (lib.caisson.hjem.mkTopConfiguration {
      configModule =
        { lib, ... }:
        {
          user = "bob";
          directory = "/home/bob";
          caisson.nvf.configurations.standalone-editor = lib.caisson.nvf.mkConfiguration {
            configModule.vim.viAlias = true;
          };
        };
    }).caisson.manifest;
  bobManifest = pkgs.writeText "manifest-bob.json" (builtins.toJSON bob.outputs.manifest);

  # The machine: the nvf configuration `editor` declared inside it, the
  # accounts of `alice` and `bob`, and the hjem configuration of `alice`
  # with the nvf configuration `hjem-editor` inside it. `bob` lingers,
  # so the systemd of `bob` runs without a login, and the machine installs the
  # hjem CLI and the manifest of `bob`.
  machine =
    { lib, ... }:
    {
      caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
        configModule.vim.viAlias = true;
      };
      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };
      users.users.bob = {
        isNormalUser = true;
        uid = 1001;
        linger = true;
      };
      caisson.hjem.configurations.alice = lib.caisson.hjem.mkConfiguration {
        configModule =
          { lib, ... }:
          {
            caisson.nvf.configurations.hjem-editor = lib.caisson.nvf.mkConfiguration {
              configModule.vim.viAlias = true;
            };
          };
      };
      environment.systemPackages = [ bob.outputs.cli ];
      environment.etc."caisson/manifest-bob.json".source = bobManifest;
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
  aliceProfile = "/home/alice/.local/state/caisson/profiles/nvf/hjem-editor";
  bobProfile = "/home/bob/.local/state/caisson/profiles/nvf/standalone-editor";
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
    # The test switches the machine, which the test framework leaves
    # out of a node by default.
    system.switch.enable = true;
  };

  testScript = ''
    def as_bob(command):
        return machine.succeed(
            f"su bob -c 'XDG_RUNTIME_DIR=/run/user/1001 {command}'"
        )

    def target_of(path):
        return machine.succeed(f"readlink -f {path}").strip()

    def change_by_hand(path, user):
        machine.succeed(
            f"su {user} -c 'nix-env --profile {path} --set $(readlink -f /run/current-system)'"
        )
        machine.fail(f"test -e {path}/bin/nvim")

    machine.wait_for_unit("caisson-profile-nvf-editor.service")

    # The unit has activated the profile of the system, and the `nvim` of
    # the machine runs the Neovim of the profile.
    machine.succeed("test -x ${profile}/bin/nvim")
    machine.succeed("test -x ${profile}/bin/vi")
    declared = target_of("${profile}")
    machine.succeed("nvim --headless +qa")

    # The profile inside the hjem configuration of `alice` is activated
    # with the files of `alice`, and a switch, which applies them again,
    # puts it back after it is changed by hand.
    machine.wait_for_unit("caisson-profile-alice-nvf-hjem-editor.service")
    machine.succeed("test -x ${aliceProfile}/bin/nvim")
    alice_declared = target_of("${aliceProfile}")
    change_by_hand("${aliceProfile}", "alice")
    machine.succeed("/run/current-system/bin/switch-to-configuration test")
    restored = target_of("${aliceProfile}")
    assert restored == alice_declared, f"the profile of alice is {restored}, not {alice_declared}"

    # The standalone hjem configuration of `bob`: the switch links the
    # units, and the systemd of `bob`, started again as a login starts
    # it, reads them and activates the profile.
    machine.wait_for_unit("user@1001.service")
    as_bob("hjem standalone switch --manifest /etc/caisson/manifest-bob.json")
    machine.succeed("systemctl restart user@1001.service")
    machine.wait_until_succeeds("test -x ${bobProfile}/bin/nvim", timeout=60)
    bob_declared = target_of("${bobProfile}")
    as_bob("systemctl --user is-active caisson-profiles.path")

    # The next switch puts the profile back after it is changed by hand.
    change_by_hand("${bobProfile}", "bob")
    as_bob("hjem standalone switch --manifest /etc/caisson/manifest-bob.json")
    machine.wait_until_succeeds("test -x ${bobProfile}/bin/nvim", timeout=60)
    restored = target_of("${bobProfile}")
    assert restored == bob_declared, f"the profile of bob is {restored}, not {bob_declared}"

    # The profile of the system is put back when the machine boots.
    change_by_hand("${profile}", "root")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("caisson-profile-nvf-editor.service")
    restored = target_of("${profile}")
    assert restored == declared, f"the profile is {restored}, not {declared}"
    machine.succeed("test -x ${profile}/bin/nvim")
  '';
}
