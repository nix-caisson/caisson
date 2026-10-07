# SPDX-License-Identifier: MIT
#
# The pin readers and the flake callers under `lib.caisson`. Each case
# is a boolean, turned into a test that expects true.
#
# The suite fetches nothing: see the comment on the pin readers below.
{ lib, parent }:
let

  inherit (lib.caisson) pins callFlake;

  # The pure parts of the pin readers, read directly.
  flakeLock = import (parent + "/lib-overlays/framework/pins/flake-lock.nix");
  npinsData = import (parent + "/lib-overlays/framework/pins/npins.nix");

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;

  # The inputs a flake's `outputs` would receive, for the pins-flake
  # fixture: `self` points at its tree (whose flake.lock is read), and
  # each input carries what Nix puts on a resolved input.
  pinsFlakeInputs = rec {
    self = {
      outPath = ./fixtures/pins-flake;
      rev = "0000000000000000000000000000000000000abc";
      shortRev = "0000000";
      lastModified = 1;
      lastModifiedDate = "19700101000001";
      narHash = "sha256-SELF";
    };
    nixpkgs = {
      outPath = "/nix/store/00000000000000000000000000000000-source";
      rev = "1111111111111111111111111111111111111111";
      narHash = "sha256-NIXPKGS";
      lastModified = 10;
      lib = "nixpkgs-lib-marker";
    };
    follower = nixpkgs;
    nonflake = {
      outPath = "/nix/store/11111111111111111111111111111111-source";
      rev = "2222222222222222222222222222222222222222";
      narHash = "sha256-NONFLAKE";
      lastModified = 20;
    };
    overridden = {
      outPath = "/nix/store/22222222222222222222222222222222-source";
      narHash = "sha256-OVERRIDE";
      lastModified = 31;
    };
    unlocked = {
      outPath = "/nix/store/33333333333333333333333333333333-source";
    };
  };

  results = {

    callFlakeWiresInputsAndSelf =
      let
        wired = callFlake {
          src = ./fixtures/hello-flake;
          inputs.greeting = {
            text = "hello";
          };
          sourceInfo.rev = "fixture";
        };
      in
      wired.message == "hello, kernel"
      && wired.viaSelf == "hello, kernel"
      && wired.selfPath == ./fixtures/hello-flake
      && wired.rev == "fixture"
      && wired._type == "flake"
      && wired.inputs.greeting.text == "hello";

    # A lockfile'd flake with no inputs has no sources.
    pinsFlakeCompatNoInputs = (pins.flake-compat ./fixtures/deps-flake).sources == { };

    # The pin readers. The suite fetches nothing: `pins.flake` reads a
    # fake inputs attrset and the fixture's lock; `pins.flake-compat` is
    # exercised on a relative path input, which is located, not fetched,
    # and its remote inputs through the lock descriptors; `pins.npins`
    # through its descriptors and the `pin` record of tarball pins,
    # whose fetch is not forced by reading the record.
    pinsFlakeSourcesAndRoot =
      let
        read = pins.flake pinsFlakeInputs;
        s = read.sources;
      in
      builtins.attrNames s == [
        "follower"
        "nixpkgs"
        "nonflake"
        "overridden"
        "unlocked"
      ]
      &&
        read.root == {
          outPath = ./fixtures/pins-flake;
          dirty = false;
          rev = "0000000000000000000000000000000000000abc";
          shortRev = "0000000";
          dirtyRev = null;
          dirtyShortRev = null;
          lastModified = 1;
          lastModifiedDate = "19700101000001";
          narHash = "sha256-SELF";
        }
      # The source is the input itself, outputs included, plus `pin`.
      && s.nixpkgs.lib == "nixpkgs-lib-marker"
      &&
        s.nixpkgs.pin == {
          system = "flake";
          files = {
            refs = "flake.nix";
            revisions = "flake.lock";
          };
          overridden = false;
          url = "github:NixOS/nixpkgs/nixos-unstable";
          follows = null;
          rev = "1111111111111111111111111111111111111111";
          narHash = "sha256-NIXPKGS";
          lastModified = 10;
        };

    pinsFlakeFollowsNonFlakeAndOverride =
      let
        s = (pins.flake pinsFlakeInputs).sources;
      in
      # A follows is the tree it lands on, with the path it follows.
      s.follower.pin.follows == [ "nixpkgs" ]
      && s.follower.pin.url == "github:NixOS/nixpkgs/nixos-unstable"
      && s.follower.pin.rev == s.nixpkgs.pin.rev
      && s.nixpkgs.pin.follows == null
      && s.nonflake.pin.url == "git+https://example.com/nonflake.git?ref=main"
      && !s.nonflake.pin.overridden
      # The resolved tree differs from the lock: an override was in force.
      && s.overridden.pin.overridden
      && s.overridden.pin.narHash == "sha256-OVERRIDE"
      # An input the lock does not name carries no ref.
      && s.unlocked.pin.url == null
      && !s.unlocked.pin.overridden;

    # Inside a flake's `outputs`, `self` cannot be read while the
    # outputs are being computed, and the lock is read from `self`. A
    # source's `pin` has names known without reading the lock, so
    # asking what a pin holds leaves `self` unread.
    pinsFlakePinNamesDoNotReadTheLock =
      builtins.attrNames
        (pins.flake {
          self = throw "self forced";
          nixpkgs = pinsFlakeInputs.nixpkgs;
        }).sources.nixpkgs.pin == [
        "files"
        "follows"
        "lastModified"
        "narHash"
        "overridden"
        "rev"
        "system"
        "url"
      ];

    # A bare path or string input is a tree with that out path.
    pinsFlakeBareInput =
      let
        s =
          (pins.flake {
            self.outPath = ./fixtures/pins-plain-dir;
            bare = "/nix/store/44444444444444444444444444444444-source";
          }).sources;
      in
      s.bare.outPath == "/nix/store/44444444444444444444444444444444-source"
      && s.bare.pin.system == "flake"
      && !s.bare.pin.overridden;

    pinsFlakeDirtyRoot =
      (pins.flake {
        self = {
          outPath = ./fixtures/pins-flake;
          dirtyRev = "0000000000000000000000000000000000000abc-dirty";
          lastModified = 2;
        };
      }).root == {
        outPath = ./fixtures/pins-flake;
        dirty = true;
        rev = null;
        shortRev = null;
        dirtyRev = "0000000000000000000000000000000000000abc-dirty";
        dirtyShortRev = null;
        lastModified = 2;
        lastModifiedDate = null;
        narHash = null;
      };

    # Inside a flake's `outputs`, asking which attributes `self` has
    # forces the outputs being computed. The root's names are fixed, so
    # a root read from a `self` that must not be forced is still a set
    # whose names can be read.
    pinsFlakeRootNamesDoNotForceSelf =
      builtins.attrNames (pins.flake { self = throw "self forced"; }).root == [
        "dirty"
        "dirtyRev"
        "dirtyShortRev"
        "lastModified"
        "lastModifiedDate"
        "narHash"
        "outPath"
        "rev"
        "shortRev"
      ];

    pinsFlakeRefusesMissingSelfAndOldLock =
      throws (pins.flake { nixpkgs = { }; }).root
      &&
        throws
          (pins.flake {
            self.outPath = ./fixtures/pins-flake-v4;
            x.narHash = "sha256-X";
          }).sources.x.pin;

    pinsFlakeCompatRelativeInput =
      let
        s = (pins.flake-compat ./fixtures/pins-flake-compat).sources;
      in
      builtins.attrNames s == [
        "alias"
        "local"
        "localFlake"
        "nested"
        "remote"
      ]
      && s.local.outPath == ./fixtures/pins-flake-compat/sub
      && builtins.pathExists (s.local.outPath + "/marker")
      &&
        s.local.pin == {
          system = "flake";
          files = {
            refs = "flake.nix";
            revisions = "flake.lock";
          };
          dir = ./fixtures/pins-flake-compat;
          url = "path:./sub";
          follows = null;
        }
      && s.alias.outPath == s.local.outPath
      && s.alias.pin.follows == [ "local" ];

    # A flake input comes with its outputs, as Nix hands it over, so a
    # partition's `extraInputs` can read `inputs.<name>.flakeModule`.
    pinsFlakeCompatFlakeInputCarriesOutputs =
      let
        s = (pins.flake-compat ./fixtures/pins-flake-compat).sources;
      in
      s.localFlake.flakeModule == "the-module"
      && s.localFlake._type == "flake"
      && s.localFlake.outputs.flakeModule == "the-module"
      && s.localFlake.outPath == ./fixtures/pins-flake-compat/subflake
      && s.localFlake.pin.url == "path:./subflake"
      && !(s.local ? outputs);

    pinsFlakeCompatRefusals =
      let
        s = (pins.flake-compat ./fixtures/pins-flake-compat).sources;
      in
      throws s.nested.outPath
      && throws (pins.flake-compat ./fixtures/pins-plain-dir).sources
      && throws (pins.flake-compat ./fixtures/pins-flake-v4).sources;

    pinsFlakeLockDescriptors =
      let
        d = flakeLock.descriptors (flakeLock.readLock ./fixtures/pins-flake-compat);
      in
      d.remote == {
        node = "remote";
        locked = {
          dir = "pkg";
          lastModified = 40;
          narHash = "sha256-REMOTE";
          owner = "example";
          repo = "remote";
          rev = "4444444444444444444444444444444444444444";
          type = "github";
        };
        original = {
          dir = "pkg";
          owner = "example";
          ref = "v1";
          repo = "remote";
          type = "github";
        };
        flake = true;
        relative = false;
        parent = [ ];
      }
      && d.nested.node == "inner"
      &&
        d.nested.follows == [
          "remote"
          "inner"
        ]
      && d.nested.relative
      && d.nested.parent == [ "remote" ]
      && flakeLock.refToString d.remote.original == "github:example/remote/v1?dir=pkg";

    # The fallback renderer, used where the evaluator has no
    # flakeRefToString, renders as the evaluator does.
    pinsFlakeRefFallbackRenders =
      builtins.map flakeLock.renderRef [
        {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
        }
        {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          ref = "nixos-unstable";
        }
        {
          type = "github";
          owner = "a";
          repo = "b";
          ref = "main";
          dir = "sub";
        }
        {
          type = "github";
          owner = "a";
          repo = "b";
          host = "git.example.com";
        }
        {
          type = "git";
          url = "https://example.com/x.git";
          ref = "main";
          submodules = true;
        }
        {
          type = "path";
          path = "./sub";
        }
        {
          type = "indirect";
          id = "nixpkgs";
          ref = "nixos-24.05";
        }
        {
          type = "tarball";
          url = "https://example.com/x.tar.gz";
        }
      ] == [
        "github:NixOS/nixpkgs"
        "github:NixOS/nixpkgs/nixos-unstable"
        "github:a/b/main?dir=sub"
        "github:a/b?host=git.example.com"
        "git+https://example.com/x.git?ref=main&submodules=1"
        "path:./sub"
        "flake:nixpkgs/nixos-24.05"
        "https://example.com/x.tar.gz"
      ];

    pinsNpinsDescriptors =
      let
        d = npinsData.describe "test" (
          builtins.fromJSON (builtins.readFile ./fixtures/pins-npins/sources.json)
        );
      in
      d.github == {
        type = "Git";
        hash = "sha256-GITHUB";
        url = "https://github.com/nixos/nixpkgs.git";
        rev = "5555555555555555555555555555555555555555";
        narHash = "sha256-GITHUB";
        fetch.tarball = {
          url = "https://github.com/nixos/nixpkgs/archive/5555555555555555555555555555555555555555.tar.gz";
          sha256 = "sha256-GITHUB";
        };
      }
      # Submodules take the git fetch, as npins does.
      &&
        d.plain-git.fetch.git == {
          url = "https://example.com/plain.git";
          submodules = true;
          rev = "6666666666666666666666666666666666666666";
          narHash = "sha256-PLAIN";
          name = "source";
        }
      && d.channel.narHash == "sha256-CHANNEL"
      && !(d.channel ? rev)
      # A file that is not unpacked has a flat hash, no narHash.
      && d.file.fetch ? file
      && !(d.file ? narHash);

    pinsNpinsSourceRecord =
      let
        s = (pins.npins ./fixtures/pins-npins).sources;
      in
      s.github.pin == {
        system = "npins";
        files = {
          refs = "sources.json";
          revisions = "sources.json";
        };
        dir = ./fixtures/pins-npins;
        url = "https://github.com/nixos/nixpkgs.git";
        hash = "sha256-GITHUB";
        rev = "5555555555555555555555555555555555555555";
        narHash = "sha256-GITHUB";
      };

    pinsNpinsRefusals =
      throws (pins.npins ./fixtures/pins-npins).sources.container.pin
      && throws (pins.npins ./fixtures/pins-npins-v5).sources
      && throws (pins.npins ./fixtures/pins-plain-dir).sources;

    pinsGitRootOutsideGit =
      pins.gitRoot ./fixtures/pins-plain-dir == {
        outPath = ./fixtures/pins-plain-dir;
        dirty = false;
        rev = null;
        shortRev = null;
        dirtyRev = null;
        dirtyShortRev = null;
        lastModified = null;
        lastModifiedDate = null;
        narHash = null;
      };

  };

in
builtins.listToAttrs (
  builtins.map (name: {
    name = "test: ${name}";
    value = {
      expr = results.${name};
      expected = true;
    };
  }) (builtins.attrNames results)
)
