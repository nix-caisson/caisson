# SPDX-License-Identifier: MIT
#
# A NixOS test of the profiles a machine activates, run in a VM, through
# sequences of changes at each level that activates a profile.
# `inputs` is the dependency pool of the checks partition with
# `caisson` set to the tree itself.
#
# The declarations come in the versions v1 and v2. The Neovim of v2
# has `vim` beside `nvim` and `vi`, and a file of each hjem
# configuration holds the name of the version.
#
# The machine declares, in v1, the nvf configuration `editor` inside
# it, kept in the profile of the system
# `/nix/var/nix/profiles/caisson/nvf/editor`, and a hjem configuration
# for the user `alice` with the nvf configuration `hjem-editor` inside
# it, kept in a profile in the home directory of `alice`. The
# specialisation `v2` of the machine declares them in v2. The test boots
# the machine, switches to v2 and back, and checks after each step that
# the profiles and the file of `alice` are those of the version the
# machine runs. It checks that a switch puts the profile of `alice`
# back after it is changed by hand, and that a boot does the same for
# the profile of the system.
#
# The user `bob` has a hjem configuration that is a top, with the nvf
# configuration `standalone-editor` inside it, applied with
# `hjem standalone switch`, as on a machine that caisson does not
# manage. The test applies v1, which activates nothing until the
# systemd of `bob` reads the units in the files of `bob`, starts that systemd
# again as a login does, and then switches to v2, rolls back with
# `hjem standalone rollback`, changes the profile by hand and switches
# to v1, switches to v2 from a Nix file with `--config`, and switches
# to v1 from a flake with `--flake`. After each step it checks the
# profile and the file of `bob`.
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

  # The nvf module of a version: the Neovim of v2 also has `vim`.
  editorOf = version: {
    vim.viAlias = true;
    vim.vimAlias = version == "v2";
  };

  # A hjem module of a version: the file that names the version, and the
  # nvf configuration `name` inside it.
  hjemOf =
    version: name:
    { lib, ... }:
    {
      files.".config/probe/version".text = version;
      caisson.nvf.configurations.${name} = lib.caisson.nvf.mkConfiguration {
        configModule = editorOf version;
      };
    };

  # The hjem configuration of `bob` in a version, applied with
  # `hjem standalone switch`, and its manifest as the file the CLI reads.
  bobOf =
    version:
    (lib.caisson.hjem.mkTopConfiguration {
      configModule = {
        imports = [ (hjemOf version "standalone-editor") ];
        user = "bob";
        directory = "/home/bob";
      };
    }).caisson.manifest;
  bobManifest =
    version:
    pkgs.writeText "manifest-bob-${version}.json" (builtins.toJSON (bobOf version).outputs.manifest);

  # A Nix file that evaluates to the manifest of `bob` in a version. The
  # JSON is written into the file as a Nix string, so the file refers to
  # the store paths of the manifest, which keeps them in the closure of
  # the machine, and evaluating it inside the machine needs nothing else.
  bobNix =
    version:
    pkgs.writeText "manifest-bob-${version}.nix" ''
      builtins.fromJSON ${builtins.toJSON (builtins.toJSON (bobOf version).outputs.manifest)}
    '';

  # A flake whose `hjemConfigurations.bob` is the manifest of `bob` in a
  # version, which `hjem standalone switch --flake` reads.
  bobFlake =
    version:
    pkgs.runCommand "hjem-bob-${version}-flake" { } ''
      mkdir $out
      cp ${bobNix version} $out/manifest.nix
      cat > $out/flake.nix <<'EOF'
      {
        outputs = _: { hjemConfigurations.bob = import ./manifest.nix; };
      }
      EOF
    '';

  # What the machine declares in a version: the nvf configuration
  # `editor`, and the hjem configuration of `alice` with the nvf
  # configuration `hjem-editor` inside it. Each is a definition the
  # specialisation `v2` replaces.
  declarationsOf =
    version: lib:
    let
      force = if version == "v1" then (value: value) else lib.mkForce;
    in
    {
      caisson.nvf.configurations.editor = force (
        lib.caisson.nvf.mkConfiguration { configModule = editorOf version; }
      );
      caisson.hjem.configurations.alice = force (
        lib.caisson.hjem.mkConfiguration { configModule = hjemOf version "hjem-editor"; }
      );
    };

  # The machine: v1 of the declarations, the accounts of `alice` and
  # `bob`, the hjem CLI, and the manifests of `bob`. `bob` lingers, so
  # the systemd of `bob` runs without a login.
  machine =
    { lib, ... }:
    {
      config = declarationsOf "v1" lib // {
        users.users.alice = {
          isNormalUser = true;
          uid = 1000;
        };
        users.users.bob = {
          isNormalUser = true;
          uid = 1001;
          linger = true;
        };
        environment.systemPackages = [ (bobOf "v1").outputs.cli ];
        environment.etc = {
          "caisson/manifest-bob-v1.json".source = bobManifest "v1";
          "caisson/manifest-bob-v2.json".source = bobManifest "v2";
          "caisson/hjem-bob-v2.nix".source = bobNix "v2";
          "caisson/hjem-bob-v1-flake".source = bobFlake "v1";
        };
        # `hjem standalone switch --config` and `--flake` evaluate with
        # `nix eval`.
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
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
    specialisation.v2.configuration = { lib, ... }: declarationsOf "v2" lib;
  };

  testScript =
    { nodes, ... }:
    let
      v1 = nodes.machine.system.build.toplevel;
    in
    ''
      def as_user(user, command):
          uid = {"alice": 1000, "bob": 1001}[user]
          return machine.succeed(
              f"su {user} -c 'XDG_RUNTIME_DIR=/run/user/{uid} {command}'"
          )

      def target_of(path):
          return machine.succeed(f"readlink -f {path}").strip()

      def change_by_hand(path, user):
          machine.succeed(
              f"su {user} -c 'nix-env --profile {path} --set $(readlink -f /run/current-system)'"
          )
          machine.fail(f"test -e {path}/bin/nvim")

      # The profile at `path` holds the Neovim of `version`: v2 has
      # `vim`, v1 has not. A user's profile is activated by a unit, so
      # the check waits for it.
      def holds(path, version):
          machine.wait_until_succeeds(f"test -x {path}/bin/nvim", timeout=60)
          if version == "v2":
              machine.wait_until_succeeds(f"test -x {path}/bin/vim", timeout=60)
          else:
              machine.wait_until_fails(f"test -e {path}/bin/vim", timeout=60)

      # The file of the hjem configuration of `user` names `version`.
      def has_file(user, version):
          machine.wait_until_succeeds(
              f"grep -qx {version} /home/{user}/.config/probe/version", timeout=60
          )

      def switch_to(toplevel):
          machine.succeed(f"{toplevel}/bin/switch-to-configuration test")

      # The machine boots in v1: the profile of the system, the files of
      # `alice` and the profile of `alice`.
      machine.wait_for_unit("caisson-profile-nvf-editor.service")
      machine.wait_for_unit("caisson-profile-alice-nvf-hjem-editor.service")
      holds("${profile}", "v1")
      holds("${aliceProfile}", "v1")
      has_file("alice", "v1")
      declared = target_of("${profile}")
      alice_declared = target_of("${aliceProfile}")
      machine.succeed("nvim --headless +qa")

      # A switch puts the profile of `alice` back after it is changed by
      # hand.
      change_by_hand("${aliceProfile}", "alice")
      switch_to("${v1}")
      holds("${aliceProfile}", "v1")
      restored = target_of("${aliceProfile}")
      assert restored == alice_declared, f"the profile of alice is {restored}, not {alice_declared}"

      # The machine switches to v2, and back to v1.
      switch_to("${v1}/specialisation/v2")
      holds("${profile}", "v2")
      holds("${aliceProfile}", "v2")
      has_file("alice", "v2")
      switch_to("${v1}")
      holds("${profile}", "v1")
      holds("${aliceProfile}", "v1")
      has_file("alice", "v1")
      restored = target_of("${profile}")
      assert restored == declared, f"the profile is {restored}, not {declared}"

      # The first switch of `bob` links the units, which the systemd of
      # `bob` has not read, so the profile is not yet activated. The
      # systemd of `bob`, started again as a login starts it, reads them
      # and activates the profile.
      machine.wait_for_unit("user@1001.service")
      as_user("bob", "hjem standalone switch --manifest /etc/caisson/manifest-bob-v1.json")
      has_file("bob", "v1")
      machine.fail("test -e ${bobProfile}")
      machine.succeed("systemctl restart user@1001.service")
      holds("${bobProfile}", "v1")
      bob_declared = target_of("${bobProfile}")
      as_user("bob", "systemctl --user is-active caisson-profiles.path")

      # A switch to v2, and a rollback to v1.
      as_user("bob", "hjem standalone switch --manifest /etc/caisson/manifest-bob-v2.json")
      holds("${bobProfile}", "v2")
      has_file("bob", "v2")
      as_user("bob", "hjem standalone rollback")
      holds("${bobProfile}", "v1")
      has_file("bob", "v1")

      # A switch puts the profile back after it is changed by hand.
      change_by_hand("${bobProfile}", "bob")
      as_user("bob", "hjem standalone switch --manifest /etc/caisson/manifest-bob-v1.json")
      holds("${bobProfile}", "v1")
      restored = target_of("${bobProfile}")
      assert restored == bob_declared, f"the profile of bob is {restored}, not {bob_declared}"

      # A switch from a Nix file, and a switch from a flake, which hjem
      # evaluates.
      as_user("bob", "hjem standalone switch --config /etc/caisson/hjem-bob-v2.nix")
      holds("${bobProfile}", "v2")
      has_file("bob", "v2")
      machine.succeed(
          "cp -rL /etc/caisson/hjem-bob-v1-flake /home/bob/hjem-flake"
          " && chmod -R u+w /home/bob/hjem-flake && chown -R bob /home/bob/hjem-flake"
      )
      as_user("bob", "hjem standalone switch --flake path:/home/bob/hjem-flake")
      holds("${bobProfile}", "v1")
      has_file("bob", "v1")

      # The profile of the system is put back when the machine boots.
      change_by_hand("${profile}", "root")
      machine.shutdown()
      machine.start()
      machine.wait_for_unit("caisson-profile-nvf-editor.service")
      holds("${profile}", "v1")
      restored = target_of("${profile}")
      assert restored == declared, f"the profile is {restored}, not {declared}"
    '';
}
