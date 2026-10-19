# SPDX-License-Identifier: MIT
#
# A NixOS test of what a machine activates, run in a VM, through
# sequences of changes at each level that activates something: the
# homes, the hjem configurations and the profiles declared inside the
# machine, and a standalone hjem configuration. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the
# tree itself.
#
# The declarations come in the versions v1 and v2. The Neovim of v2
# has `vim` beside `nvim` and `vi`, and a file of each home and each
# hjem configuration names the version.
#
# The machine declares, in v1 (`declarationsOf` below), the profiles of
# the system `editor` and `retired`, a hjem configuration for `alice`
# with a profile inside it, and the homes of `carol` and `dave`, each
# with a profile inside it. The specialisation `v2` declares v2, which
# drops `retired` and adds the home of `erin`. The test boots the
# machine, switches to v2 and back, and checks after each step that the
# profiles, the files and the units are those of the version the
# machine runs. It checks that a switch puts the profile of `alice` back
# after it is changed by hand, and that a boot puts the profiles of the
# system and of `carol` back.
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
      inherit (inputs)
        nixpkgs
        nvf
        hjem
        home-manager
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

  # A home in a version: the file that names the version, and the nvf
  # configuration `home-editor` inside it, which the home activates.
  homeOf =
    version: lib: extra:
    lib.caisson.home-manager.mkConfiguration {
      configModule =
        { lib, ... }:
        {
          imports = [ extra ];
          home.stateVersion = "25.05";
          home.file.".config/probe/version".text = version;
          caisson.nvf.configurations.home-editor = lib.caisson.nvf.mkConfiguration {
            configModule = editorOf version;
          };
        };
    };

  # What the machine declares in a version. The specialisation `v2`
  # replaces each set of configurations whole, which also removes what
  # v1 has and v2 has not:
  #
  # - the nvf configuration `editor`, and in v1 alone `retired`, each a
  #   profile of the system;
  # - the hjem configuration of `alice` with the nvf configuration
  #   `hjem-editor` inside it;
  # - the homes of `carol`, whose account the machine declares, and of
  #   `dave`, whose account is declared elsewhere, and in v2 alone the
  #   home of `erin`.
  declarationsOf =
    version: lib:
    let
      force = if version == "v1" then (value: value) else lib.mkForce;
    in
    {
      caisson.nvf.configurations = force (
        {
          editor = lib.caisson.nvf.mkConfiguration { configModule = editorOf version; };
        }
        // lib.optionalAttrs (version == "v1") {
          retired = lib.caisson.nvf.mkConfiguration { configModule = editorOf version; };
        }
      );
      caisson.hjem.configurations = force {
        alice = lib.caisson.hjem.mkConfiguration { configModule = hjemOf version "hjem-editor"; };
      };
      caisson.home-manager.configurations = force (
        {
          carol = homeOf version lib { };
          dave = homeOf version lib { home.homeDirectory = "/home/dave"; };
        }
        // lib.optionalAttrs (version == "v2") {
          erin = homeOf version lib { };
        }
      );
    };

  # The machine: v1 of the declarations, the accounts of `alice`, `bob`,
  # `carol` and `erin`, the hjem CLI, and the manifests of `bob`. `bob`
  # lingers, so the systemd of `bob` runs without a login. The account
  # of `dave` is declared elsewhere: the test creates it, as
  # systemd-homed or a directory service would provide it. `editor` is
  # the profile `nvim` runs where several share its variable.
  machine =
    { lib, ... }:
    {
      config = lib.mkMerge [
        (declarationsOf "v1" lib)
        {
          users.users.alice = {
            isNormalUser = true;
            uid = 1000;
          };
          users.users.bob = {
            isNormalUser = true;
            uid = 1001;
            linger = true;
          };
          users.users.carol = {
            isNormalUser = true;
            uid = 1002;
          };
          users.users.erin = {
            isNormalUser = true;
            uid = 1004;
          };
          caisson.home-manager.activation.usersDeclaredElsewhere = [ "dave" ];
          caisson.profiles.selected.CAISSON_NVIM_PROFILE = "nvf/editor";
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
        }
      ];
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
  name = "caisson-activation-vm";

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
    # The test boots the machine again, and what the first boot added to
    # the store, such as the environments of the homes, must still be
    # there, as on a machine whose store is on its disk.
    virtualisation.writableStoreUseTmpfs = false;
    specialisation.v2.configuration = { lib, ... }: declarationsOf "v2" lib;
  };

  testScript =
    { nodes, ... }:
    let
      v1 = nodes.machine.system.build.toplevel;
    in
    ''
      def as_user(user, command):
          uid = {"alice": 1000, "bob": 1001, "carol": 1002, "dave": 1003, "erin": 1004}[user]
          return machine.succeed(
              f"su {user} -c 'XDG_RUNTIME_DIR=/run/user/{uid} {command}'"
          )

      def profile_of(user, name):
          return f"/home/{user}/.local/state/caisson/profiles/nvf/{name}"

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

      # The file of the home or the hjem configuration of `user` names
      # `version`.
      def has_file(user, version):
          machine.wait_until_succeeds(
              f"grep -qx {version} /home/{user}/.config/probe/version", timeout=60
          )

      def switch_to(toplevel):
          machine.succeed(f"{toplevel}/bin/switch-to-configuration test")

      # Everything the machine activates is in `version`: the profile of
      # the system, the hjem configuration of `alice`, the homes of
      # `carol` and `dave`, and the profiles inside them.
      def is_at(version):
          holds("${profile}", version)
          for user, name in [("alice", "hjem-editor"), ("carol", "home-editor"), ("dave", "home-editor")]:
              holds(profile_of(user, name), version)
              has_file(user, version)

      # The machine boots in v1. The account of `dave`, which the machine
      # does not declare, is created, and lingers, so the service manager
      # of `dave` starts and activates the home with its user unit.
      #
      # A switch starts the new units through the active targets, and
      # `multi-user.target` is active only once the boot has reached it,
      # which `dhcpcd` delays in the VM.
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("caisson-profile-nvf-editor.service")
      machine.wait_for_unit("caisson-profile-nvf-retired.service")
      machine.wait_for_unit("caisson-profile-alice-nvf-hjem-editor.service")
      machine.wait_for_unit("home-manager-carol.service")
      machine.succeed("useradd --create-home --uid 1003 dave")
      machine.succeed("loginctl enable-linger dave")
      machine.wait_for_unit("user@1003.service")
      is_at("v1")
      holds("/nix/var/nix/profiles/caisson/nvf/retired", "v1")
      machine.fail("systemctl cat home-manager-erin.service")
      declared = target_of("${profile}")
      alice_declared = target_of(profile_of("alice", "hjem-editor"))
      carol_declared = target_of(profile_of("carol", "home-editor"))
      machine.succeed("nvim --headless +qa")

      # A switch puts the profile of `alice` back after it is changed by
      # hand.
      change_by_hand(profile_of("alice", "hjem-editor"), "alice")
      switch_to("${v1}")
      holds(profile_of("alice", "hjem-editor"), "v1")
      restored = target_of(profile_of("alice", "hjem-editor"))
      assert restored == alice_declared, f"the profile of alice is {restored}, not {alice_declared}"

      # The machine switches to v2: everything follows, the unit of the
      # removed profile `retired` is gone, and the added home of `erin`
      # is activated.
      switch_to("${v1}/specialisation/v2")
      is_at("v2")
      machine.fail("systemctl cat caisson-profile-nvf-retired.service")
      machine.wait_for_unit("home-manager-erin.service")
      holds(profile_of("erin", "home-editor"), "v2")
      has_file("erin", "v2")

      # And back to v1: everything follows, and the unit of the removed
      # home of `erin` is gone.
      switch_to("${v1}")
      is_at("v1")
      machine.fail("systemctl cat home-manager-erin.service")
      machine.wait_for_unit("caisson-profile-nvf-retired.service")
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

      # The profiles of the system and of `carol` are put back when the
      # machine boots.
      change_by_hand("${profile}", "root")
      change_by_hand(profile_of("carol", "home-editor"), "carol")
      machine.shutdown()
      machine.start()
      machine.wait_for_unit("caisson-profile-nvf-editor.service")
      machine.wait_for_unit("home-manager-carol.service")
      holds("${profile}", "v1")
      holds(profile_of("carol", "home-editor"), "v1")
      restored = target_of("${profile}")
      assert restored == declared, f"the profile is {restored}, not {declared}"
      restored = target_of(profile_of("carol", "home-editor"))
      assert restored == carol_declared, f"the profile of carol is {restored}, not {carol_declared}"
    '';
}
