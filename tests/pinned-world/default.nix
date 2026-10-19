# SPDX-License-Identifier: MIT
#
# The pinned-world suite: caisson, the tree this file lives in,
# composed with concrete pinned versions of the upstream world
# (nixpkgs, home-manager, colmena, disko, nix-darwin, terranix,
# system-manager, read from tests/dependencies) and exercised end to end. Every upstream
# expectation caisson relies on is held by a probe here, so a pin
# that moves and breaks an expectation fails at evaluation, in this
# suite, rather than in a consumer.
#
# The checks partition runs it as the `pinned-world` check, so
# `nix flake check` evaluates the suite at the committed pins and a
# change to caisson is judged against the last known good world. The
# drift workflow advances the pins in the working tree, committing
# nothing, and runs the same check against today's upstreams.
#
# `inputs` is the dependency pool of the checks partition with
# `caisson` set to the tree itself. caisson-core is read through the
# tree's composed library, `inputs.caisson.lib.caisson-core`, the
# core caisson pins; the suite composes no other.
{ inputs }:

let

  core = inputs.caisson.lib.caisson-core;
  inherit (core) compose resolve;

  # caisson's integrations as the keyed entries a registry holds: the
  # overlays caisson exports, registered by mkLib from the `projects`
  # entry `caisson` and read back from the manifest, each keyed
  # `caisson/<name>` and importing the published nixpkgs-lib entry. The suite composes them with
  # caisson-core's `compose` directly, the way mkLib does, so the
  # composition guarantees are probed on the real entries. The
  # `nixpkgs-lib` import each exported overlay carries is the entry of
  # the tree that built it, caisson's pin; mkLib replaces every
  # published key with the composing tree's entry, and a direct
  # composition does the same by listing the world's entry, since the
  # last occurrence of a key supplies its value.
  registered =
    (core.mkLib {
      sources = { };
      defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
      projects.caisson = inputs.caisson;
    }).caisson-core.libManifest.libOverlays;

  # The registry names of caisson-core's entries, read from the
  # registry: which entries caisson-core is made of is not something
  # caisson relies on, so the suite does not list them. caisson-core
  # runs this suite against its own branches, and a branch that adds
  # or removes an entry must not fail here for that alone.
  coreNames = builtins.filter (name: builtins.match "caisson-core/.*" name != null) (
    builtins.attrNames registered
  );

  composed = compose {
    entries = builtins.map (name: registered.${name}) coreNames ++ [
      registered."caisson/integrations"
      registered."caisson/flake-parts"
      registered."caisson/tooling"
      registered."caisson/nixpkgs"
      registered."caisson/nixos"
      registered."caisson/nixos-minimal"
      registered."caisson/home-manager"
      registered."caisson/hjem"
      registered."caisson/caisson-colmena"
      registered."caisson/colmena"
      registered."caisson/caisson-disko"
      registered."caisson/disko"
      registered."caisson/caisson-facter"
      registered."caisson/facter"
      registered."caisson/darwin"
      registered."caisson/terranix"
      registered."caisson/system-manager"
      registered."caisson/treefmt"
      registered."caisson/nvf"
      registered."caisson/nixvim"
      registered."caisson/topology"
      registered."caisson/kubenix"
      registered."caisson/nixidy"
      registered."caisson/structural"
      # Last, so its value replaces the pin the overlays carry while
      # its position stays where the first import placed it.
      registered."caisson/nixpkgs-lib"
    ];
  };

  # What lives under `caisson`: the integrations, the pkgs-dependent
  # tooling, and the names of the framework a tree writes, which the
  # `framework` overlay publishes from `caisson-core`.
  expectedCaissonNames = [
    "caisson-colmena"
    "caisson-disko"
    "caisson-facter"
    "callConsumerFlake"
    "callFlake"
    "colmena"
    "configs"
    "darwin"
    "disko"
    "ecosystemSrc"
    "elide"
    "eval-weight"
    "evalManifest"
    "facter"
    "finalizeTop"
    "flake-parts"
    "hjem"
    "home-manager"
    "importApply"
    "integrations"
    "kubenix"
    "libManifest"
    "libOverlays"
    "manifestOf"
    "mkLib"
    "mkLibOverlay"
    "mkLibOverlays"
    "mkMemoizedDerivationRead"
    "mkModule"
    "mkModules"
    "mkPkgOverlay"
    "mkPkgOverlays"
    "modules"
    "nixidy"
    "nixos"
    "nixos-minimal"
    "nixpkgs"
    "nixvim"
    "nvf"
    "pins"
    "pkgOverlays"
    "pkgOverlaysFor"
    "pkgsManifest"
    "realizeInputs"
    "structural"
    "system-manager"
    "terranix"
    "topology"
    "treefmt"
  ];

  expectedCoreNames = [
    "compose"
    "coreEntries"
    "ecosystemSrc"
    "evalManifest"
    "importApply"
    "libManifest"
    "mkExtendedLib"
    "mkLib"
    "mkLibOverlay"
    "mkLibOverlays"
    "mkModule"
    "mkModules"
    "pkgsManifest"
    "resolve"
  ];

  # Every name in `expected` is among `actual`. The probes hold caisson
  # to the names it relies on; a name caisson-core adds beside them is
  # not caisson's to refuse, so an addition upstream passes and a removal
  # or rename fails.
  includesAll = expected: actual: builtins.all (name: builtins.elem name actual) expected;

  pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };

  # What a composition declares for the configurations evaluated on
  # it: the system, and a package config whose set for that system is
  # `pkgs`, marked so a configuration can show it runs on this set and
  # not on nixpkgs imported again.
  declaresPkgs = {
    systems = [ "x86_64-linux" ];
    pkgSets = _lib: {
      default =
        { name, parent }:
        {
          _type = "caisson-manifest";
          type = "nixpkgs";
          inherit name parent;
          children.nixpkgs.x86_64-linux = {
            _type = "caisson-manifest";
            type = "nixpkgs";
            name = "x86_64-linux";
            value = pkgs // {
              pinnedWorldProbe = "the set the composition declares";
            };
          };
        };
    };
  };

  minimalNixosBase =
    { ... }:
    {
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };
      system.stateVersion = "25.05";
    };

  # The colmena and disko probes compose with declared ecosystems: a
  # node resolves the colmena source, a layout resolves the disko
  # source, and nixpkgs resolves from the declaration, as it does in a
  # consumer flake.
  hiveLib = core.mkLib (
    declaresPkgs
    // {
      sources = { };
      projects = {
        caisson = inputs.caisson;
      };
      defaultEcosystemSrc = {
        inherit (inputs)
          nixpkgs
          colmena
          flake-parts
          disko
          ;
      };
    }
  );

  # Disk layouts as disko writes them, from disko's examples: a disk
  # with an ESP and LUKS around LVM, and one with mdadm, ZFS, LUKS and
  # LVM over three disks.
  luksLvmLayout = import "${inputs.disko}/example/luks-lvm.nix";
  complexLayout = import "${inputs.disko}/example/complex.nix";

  # What a machine installed onto a layout needs beside the layout,
  # which gives it its file systems.
  diskoMachineBase = {
    boot.loader.grub.enable = false;
    system.stateVersion = "25.05";
  };

  # The machine NixOS builds from the NixOS module of disko, the layout
  # and `diskoMachineBase`, with no caisson involved. It is named
  # `nas-1`, the host name caisson gives the machine declared as
  # `nas-1`.
  upstreamDiskoMachine =
    layout:
    import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
      system = "x86_64-linux";
      modules = [
        "${inputs.disko}/module.nix"
        layout
        diskoMachineBase
        { networking.hostName = "nas-1"; }
      ];
    };

  # A top holding a disko configuration of `integration` named
  # `nas-1`, over `layout`. With `machine`, a NixOS module, the layout
  # declares a NixOS configuration named `nas-1` from it, installed onto
  # the layout. `args` are further arguments passed to `mkConfiguration`
  # for the layout.
  layoutTop =
    {
      integration,
      layout,
      machine ? null,
      args ? { },
    }:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.${integration}.configurations.nas-1 = lib.caisson.${integration}.mkConfiguration (
            args
            // {
              configModule =
                { lib, ... }:
                {
                  imports = [ layout ];
                }
                // (
                  if machine == null then
                    { }
                  else
                    {
                      caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                        configModule = machine;
                      };
                    }
                );
            }
          );
        };
    };

  # The manifest of the disko configuration `nas-1` of a `layoutTop`.
  layoutManifest = integration: top: top.caisson.manifest.children.${integration}.nas-1;

  # A top holding a colmena configuration named `default`, with a NixOS
  # configuration declared inside it for each machine given, by name.
  # `machineArgs` are further arguments of each machine's constructor.
  # The colmena configuration disallows a bare `colmena apply`.
  colmenaTopWith =
    machineArgs: machines:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
            pkgSets.pkgs = pkgs;
            configModule =
              { lib, ... }:
              {
                meta.allowApplyAll = false;
                caisson.nixos.configurations = builtins.mapAttrs (
                  _: configModule: lib.caisson.nixos.mkConfiguration ({ inherit configModule; } // machineArgs)
                ) machines;
              };
          };
        };
    };
  colmenaTop = colmenaTopWith { };

  # A hive in the format colmena reads, with every feature the
  # upstream-compatible integration carries: `meta.nixpkgs`, shared and
  # per-node special arguments, `defaults` that read the node's name, a
  # node as a single module and a node as a list of modules, and a node
  # that reads another through `nodes`.
  upstreamHive = {
    meta = {
      nixpkgs = pkgs;
      allowApplyAll = false;
      specialArgs.shared = "everywhere";
      nodeSpecialArgs.beta.only = "beta";
    };
    defaults =
      { name, ... }:
      {
        imports = [ minimalNixosBase ];
        networking.hostName = name;
      };
    alpha =
      { shared, nodes, ... }:
      {
        environment.etc.shared.text = shared;
        environment.etc.peer.text = nodes.beta.config.networking.hostName;
      };
    beta = [
      (
        { only, ... }:
        {
          environment.etc.only.text = only;
        }
      )
    ];
  };

  # A top holding the upstream hive as a colmena configuration named
  # `default`.
  upstreamHiveTop = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.colmena.configurations.default = lib.caisson.colmena.mkConfiguration {
          hive = upstreamHive;
        };
      };
  };

  # A NixOS configuration with two homes declared inside it, evaluated
  # with the real home-manager over the real NixOS. The machine
  # declares the account of the first home. It does not declare the
  # account of the second, and lists that user as declared elsewhere,
  # as for an account that systemd-homed manages.
  machineWithHomes = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule =
            { lib, ... }:
            let
              home =
                module:
                lib.caisson.home-manager.mkConfiguration {
                  ecosystemSrc = inputs.home-manager;
                  configModule = {
                    imports = [ module ];
                    home.stateVersion = "25.05";
                    programs.home-manager.enable = true;
                  };
                };
            in
            {
              imports = [ minimalNixosBase ];
              users.users.declared = {
                isNormalUser = true;
                home = "/home/declared";
                uid = 1001;
              };
              caisson.home-manager.activation.usersDeclaredElsewhere = [ "undeclared" ];
              caisson.home-manager.configurations = {
                declared = home { };
                undeclared = home { home.homeDirectory = "/home/undeclared"; };
              };
            };
        };
      };
  };

  # The library of a NixOS evaluation that caisson runs. It has
  # `lib.caisson`, and it carries the manifest of that evaluation.
  #
  # The check `aNixosModuleImportsWhatDeclaresItsCaissonOptions` below
  # needs such a library without the evaluation it came from. A module
  # of the evaluation hands the library out through an option.
  nixosEvaluationLib =
    (hiveLib.caisson.nixos.mkTopConfiguration {
      ecosystemSrc = inputs.nixpkgs;
      configModule =
        { lib, ... }:
        {
          imports = [ minimalNixosBase ];
          options.pinnedWorldLib = lib.mkOption { type = lib.types.raw; };
          config.pinnedWorldLib = lib;
        };
    }).config.pinnedWorldLib;

  # Evaluates a NixOS system from one module of caisson, with what
  # that module imports and nothing else from caisson.
  #
  # caisson adds its core module to every NixOS evaluation it runs.
  # The core module declares the options under `caisson`. So inside
  # caisson, a module can use those options without importing the
  # core module, and nothing shows that the import is missing.
  #
  # This evaluation is made with the `eval-config.nix` of NixOS, so no
  # core module is added. It runs on the library above, so the module
  # finds `lib.caisson` and a manifest. A module that uses an option
  # under `caisson` therefore evaluates here only if the module
  # imports what declares that option.
  nixosSystemFromOnly =
    module:
    import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
      lib = nixosEvaluationLib;
      system = "x86_64-linux";
      specialArgs.lib = nixosEvaluationLib;
      modules = [
        minimalNixosBase
        module
      ];
    };

  results = {

    # Each NixOS module caisson registers evaluates with what it
    # imports. The modules are read from the registry, as a flake that
    # lists caisson in `projects` has them.
    aNixosModuleImportsWhatDeclaresItsCaissonOptions =
      let
        registry = hiveLib.caisson.modules.nixos;
        evaluates =
          name:
          builtins.isString
            (nixosSystemFromOnly registry."caisson/${name}").config.system.build.toplevel.drvPath;
      in
      builtins.all evaluates [
        "default"
        "home-manager-activation"
        "activation-marker"
      ];

    composesTheCaissonLibrary =
      builtins.attrNames composed.lib.caisson == expectedCaissonNames
      && includesAll expectedCoreNames (builtins.attrNames composed.lib.caisson-core)
      &&
        composed.meta.order == coreNames
        ++ [
          "caisson/framework"
          "caisson/integrations"
          "caisson/nixpkgs-lib"
          "caisson/flake-parts"
          "caisson/tooling"
          "caisson/nixpkgs"
          "caisson/nixos"
          "caisson/nixos-minimal"
          "caisson/home-manager"
          "caisson/hjem"
          "caisson/caisson-colmena"
          "caisson/colmena"
          "caisson/caisson-disko"
          "caisson/disko"
          "caisson/caisson-facter"
          "caisson/facter"
          "caisson/darwin"
          "caisson/terranix"
          "caisson/system-manager"
          "caisson/treefmt"
          "caisson/nvf"
          "caisson/nixvim"
          "caisson/topology"
          "caisson/kubenix"
          "caisson/nixidy"
          "caisson/structural"
        ];

    baseLibraryBehaves =
      composed.lib.concatStringsSep "," [
        "a"
        "b"
      ] == "a,b"
      && composed.lib ? evalModules
      && composed.lib ? mkOption;

    # The module system of the composed library comes from the declared
    # world, not from the pin of the tree that built the exported
    # overlays. The two differ as soon as tests/dependencies moves ahead
    # of caisson's lock, which is what the drift workflow does.
    composedLibraryIsTheDeclaredNixpkgsLib =
      (builtins.unsafeGetAttrPos "evalModules" composed.lib.modules).file
      == "${inputs.nixpkgs-lib}/lib/modules.nix";

    flakePartsLibReexported = composed.lib ? flake-parts;

    polyfillOverTheRealBase =
      let
        polyfill = {
          key = "pinned-world.polyfill";
          imports = [ registered."caisson/nixpkgs-lib" ];
          overlay = _final: prev: {
            compatProbe = prev.compatProbe or (x: "probe-${prev.concatStringsSep "-" x}");
          };
        };
        r = compose {
          entries = builtins.map (name: registered.${name}) coreNames ++ [ polyfill ];
        };
      in
      r.lib.compatProbe [
        "a"
        "b"
      ] == "probe-a-b"
      && r.lib ? caisson-core;

    baseReplacementLastWins =
      let
        stub = {
          key = "caisson/nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: { stubMarker = true; };
        };
        r = compose {
          entries = builtins.map (name: registered.${name}) coreNames ++ [
            registered."caisson/flake-parts"
            stub
          ];
        };
      in
      r.lib.stubMarker or false
      && !(r.lib ? evalModules)
      &&
        r.meta.order == coreNames
        ++ [
          "caisson/nixpkgs-lib"
          "caisson/framework"
          "caisson/integrations"
          "caisson/flake-parts"
        ];

    keylessPatchSeesComposedWorld =
      let
        anon = {
          key = null;
          imports = [ ];
          overlay = _final: prev: { sawCaisson = prev.caisson-core ? mkLib; };
        };
        r = compose {
          entries = [ anon ] ++ builtins.map (name: registered.${name}) coreNames;
        };
      in
      r.lib.sawCaisson;

    resolverFindsRealSource =
      resolve {
        name = "nixpkgs-lib";
        sources = { inherit (inputs) nixpkgs-lib; };
      } == inputs.nixpkgs-lib;

    integrationNamespacesPresent = builtins.all (ns: composed.lib.caisson ? ${ns}) [
      "nixpkgs"
      "nixos"
      "nixos-minimal"
      "home-manager"
      "hjem"
      "caisson-colmena"
      "colmena"
      "caisson-disko"
      "disko"
      "caisson-facter"
      "facter"
      "darwin"
      "terranix"
      "system-manager"
      "treefmt"
      "nvf"
      "nixvim"
      "topology"
      "kubenix"
      "nixidy"
    ];

    minimalNixosSystemEvaluates =
      let
        system = hiveLib.caisson.nixos-minimal.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          # The minimal evaluator carries no nixpkgs module, so the
          # package set arrives as the `pkgs` module argument.
          configModule =
            { lib, pkgs, ... }:
            {
              options.probePkgs = lib.mkOption { type = lib.types.raw; };
              config.probePkgs = pkgs;
            };
        };
      in
      system.config.probePkgs ? hello;

    ecosystemSrcValidationThrows =
      let
        throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      throws
        (hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                ecosystemSrc = { };
              };
            };
        }).colmenaHive
      &&
        throws
          (hiveLib.caisson.terranix.mkTopConfiguration {
            ecosystemSrc = { };
            configModule = { };
          }).drvPath
      &&
        throws
          (hiveLib.caisson.system-manager.mkTopConfiguration {
            ecosystemSrc = { };
            configModule = { };
          }).drvPath;

    homeConfigurationEvaluatesEndToEnd =
      let
        # A home takes its system and its package set from the
        # composition, and a top is read as the home-manager CLI
        # reads it: the evaluated home.
        home = hiveLib.caisson.home-manager.mkTopConfiguration {
          ecosystemSrc = inputs.home-manager;
          configModule =
            { ... }:
            {
              home.username = "probe";
              home.homeDirectory = "/home/probe";
              home.stateVersion = "25.05";
            };
        };
      in
      builtins.isString home.activationPackage.drvPath
      && home.config.home.username == "probe"
      # The home runs on the package set the composition declares.
      && home.pkgs.pinnedWorldProbe == "the set the composition declares"
      # The home-manager command of the home comes from the
      # home-manager source the home was evaluated with.
      && home.config.programs.home-manager.path == builtins.toString inputs.home-manager;

    # Two homes declared inside a NixOS configuration, evaluated with
    # the real home-manager over the real NixOS. The machine declares
    # the account of the first home and not the account of the
    # second, as with an account that systemd-homed manages.
    #
    # Both homes are given the Nix of the machine, and both build an
    # activation package, which forces home-manager's whole module
    # tree with the configuration of the machine handed in as
    # `osConfig`. The first home takes its home directory and its
    # user ID from the account. The second home sets its home
    # directory itself.
    homesInsideAMachineAreGivenTheMachine =
      let
        machine = machineWithHomes.nixosConfigurations.probe.config;
        declared = machineWithHomes.homeConfigurations."declared@probe";
        undeclared = machineWithHomes.homeConfigurations."undeclared@probe";
        hasTheProgram =
          home: builtins.elem home.config.programs.home-manager.package home.config.home.packages;
      in
      builtins.isString declared.activationPackage.drvPath
      && builtins.isString undeclared.activationPackage.drvPath
      && declared.config.home.homeDirectory == "/home/declared"
      && declared.config.home.uid == 1001
      && undeclared.config.home.homeDirectory == "/home/undeclared"
      && undeclared.config.home.uid == null
      && declared.config.nix.package == machine.nix.package
      && undeclared.config.nix.package == machine.nix.package
      && declared.config.submoduleSupport.enable
      && undeclared.config.submoduleSupport.enable
      && hasTheProgram declared
      && hasTheProgram undeclared;

    # The same machine activates both homes. It writes a system unit
    # for the home whose account it declares, which runs as that
    # user, and a user unit for the other home, which runs only for
    # that user. The script of each unit runs the `activate` program
    # of the activation package of its home. The system of the
    # machine evaluates with the units in it, which also checks the
    # assertions of the machine.
    aMachineActivatesTheHomesInsideIt =
      let
        machine = machineWithHomes.nixosConfigurations.probe.config;
        declared = machineWithHomes.homeConfigurations."declared@probe";
        undeclared = machineWithHomes.homeConfigurations."undeclared@probe";
        systemUnit = machine.systemd.services.home-manager-declared;
        userUnit = machine.systemd.user.services.home-manager-undeclared;
        # The script of the unit runs `activate` of the activation
        # package of the home: the string context of the script records
        # that it refers to the activation package, and the script runs
        # an `activate`.
        runs =
          unit: home:
          let
            script = unit.serviceConfig.ExecStart.text;
          in
          builtins.elem home.activationPackage.drvPath (builtins.attrNames (builtins.getContext script))
          && pkgs.lib.hasInfix "/activate" script;
      in
      systemUnit.serviceConfig.User == "declared"
      && systemUnit.unitConfig.RequiresMountsFor == "/home/declared"
      && runs systemUnit declared
      && !(runs systemUnit undeclared)
      && userUnit.unitConfig.ConditionUser == "undeclared"
      && runs userUnit undeclared
      && !(runs userUnit declared)
      && !(machine.systemd.services ? home-manager-undeclared)
      && !(machine.systemd.user.services ? home-manager-declared)
      && builtins.isString machine.system.build.toplevel.drvPath;

    # The same machine writes the file `/etc/caisson/marker.json`. The
    # file holds the digest of the system of the machine with the
    # configurations declared inside it left out.
    #
    # The system that the machine builds has the units of the homes in
    # it. So the digest in the file is the digest of the childless
    # system, and not of the system that the machine builds.
    #
    # Each home computes the same digest. The activation of each home
    # has a step that compares that digest with the file. The script of
    # the step must therefore contain the digest and the path of the
    # file.
    aMachineRecordsWhatItsHomesCompareAgainst =
      let
        machine = machineWithHomes.nixosConfigurations.probe.config;
        homes = [
          machineWithHomes.homeConfigurations."declared@probe"
          machineWithHomes.homeConfigurations."undeclared@probe"
        ];
        record = builtins.fromJSON machine.environment.etc."caisson/marker.json".text;
        digest = record.identity;
        childless =
          machineWithHomes.caisson.manifest.children.system.x86_64-linux.children.nixos.probe.childlessManifest.outputs.toplevel;
        comparesAgainstIt =
          home:
          let
            step = home.config.home.activation.caissonDrift.data;
          in
          pkgs.lib.hasInfix digest step && pkgs.lib.hasInfix "/etc/caisson/marker.json" step;
      in
      builtins.attrNames record == [ "identity" ]
      && digest == builtins.hashString "sha256" childless.outPath
      && digest != builtins.hashString "sha256" machine.system.build.toplevel.outPath
      && builtins.all comparesAgainstIt homes;

    # A NixOS configuration can be evaluated alone, with
    # `mkTopConfiguration`, or declared inside another configuration,
    # under `caisson.nixos.configurations`. The parent here gives its
    # children nothing. The machine must then be the same machine in
    # each position: its system is the same derivation.
    #
    # The machine is declared inside a structural configuration and
    # inside a flake-parts configuration. Each parent publishes it as
    # `nixosConfigurations.probe`.
    aMachineInsideAParentIsTheSameMachine =
      let
        machine = {
          ecosystemSrc = inputs.nixpkgs;
          configModule = {
            imports = [ minimalNixosBase ];
            networking.hostName = "probe";
          };
        };
        declaresTheMachine =
          { lib, ... }:
          {
            caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration machine;
          };
        alone = hiveLib.caisson.nixos.mkTopConfiguration machine;
        insideStructural =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule = declaresTheMachine;
          }).nixosConfigurations.probe;
        insideFlake =
          (hiveLib.caisson.flake-parts.mkTopConfiguration {
            configModule = declaresTheMachine;
          }).nixosConfigurations.probe;
        systemOf = configuration: configuration.config.system.build.toplevel.drvPath;
      in
      systemOf insideStructural == systemOf alone && systemOf insideFlake == systemOf alone;

    # The NixOS integration records what `nixos-rebuild` reads from a
    # configuration: the system, the VM, the VM with a boot loader,
    # and the images. Each is a reference into `config.system.build`
    # of the real NixOS. The system and both VMs are derivations, and
    # NixOS offers at least one image.
    aMachineRecordsItsSystemItsVmsAndItsImages =
      let
        outputs = nixosEvaluationLib.caisson.evalManifest.childlessManifest.outputs;
      in
      builtins.isString outputs.toplevel.drvPath
      && builtins.isString outputs.vm.drvPath
      && builtins.isString outputs.vmWithBootLoader.drvPath
      && builtins.isAttrs outputs.images
      && outputs.images != { };

    # The same for a home. A home evaluated alone and the same home
    # declared inside a structural configuration build the same
    # activation package.
    #
    # A home declared inside a machine is given the home directory,
    # the user ID and the Nix package of the machine, by modules that
    # the machine passes to its homes by default. A home that passes
    # `moduleImports` selects its modules itself and gets none of
    # them. Such a home, inside a machine, must also build the same
    # activation package as the home evaluated alone.
    aHomeInsideAParentIsTheSameHome =
      let
        home = {
          ecosystemSrc = inputs.home-manager;
          configModule = {
            home.username = "probe";
            home.homeDirectory = "/home/probe";
            home.stateVersion = "25.05";
          };
        };
        alone = hiveLib.caisson.home-manager.mkTopConfiguration home;
        insideStructural =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration home;
              };
          }).homeConfigurations.probe;
        insideMachine =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations.host = lib.caisson.nixos.mkConfiguration {
                  ecosystemSrc = inputs.nixpkgs;
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ minimalNixosBase ];
                      users.users.probe = {
                        isNormalUser = true;
                        home = "/home/probe";
                      };
                      caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration (
                        home // { moduleImports = _modules: [ ]; }
                      );
                    };
                };
              };
          }).homeConfigurations."probe@host";
        activationOf = configuration: configuration.activationPackage.drvPath;
      in
      activationOf insideStructural == activationOf alone
      && activationOf insideMachine == activationOf alone;

    # The same for a structural configuration, which builds nothing.
    # A structural configuration evaluated alone and the same
    # configuration declared inside another export the same registry
    # entries.
    aStructuralConfigurationInsideAParentExportsTheSame =
      let
        selects = {
          caisson.libOverlays.exported = overlays: { inherit (overlays) "caisson/structural"; };
        };
        alone = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = selects;
        };
        parent = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.libOverlays.exported = _overlays: { };
              caisson.structural.configurations.inner = lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule = selects;
              };
            };
        };
      in
      builtins.attrNames alone.libOverlays == [ "caisson/structural" ]
      && builtins.attrNames parent.libOverlays == builtins.attrNames alone.libOverlays;

    # An integration declares `top` when a configuration of it can be
    # a top, and only then has `mkTopConfiguration`. A colmena
    # configuration and a disko configuration are always declared
    # beneath another configuration, so their integrations declare no
    # `top`.
    onlyAnIntegrationWithATopHasMkTopConfiguration =
      hiveLib.caisson.nixos ? mkTopConfiguration
      && hiveLib.caisson.darwin ? mkTopConfiguration
      && hiveLib.caisson.home-manager ? mkTopConfiguration
      && hiveLib.caisson.hjem ? mkTopConfiguration
      && hiveLib.caisson.structural ? mkTopConfiguration
      && hiveLib.caisson.flake-parts ? mkTopConfiguration
      && !(hiveLib.caisson.caisson-colmena ? mkTopConfiguration)
      && !(hiveLib.caisson.caisson-disko ? mkTopConfiguration)
      && !(hiveLib.caisson.disko ? mkTopConfiguration);

    # A colmena configuration declared under the name `default` beneath
    # a top fills the top's `colmenaHive`. Its nodes are the NixOS
    # configurations declared inside it, which the top also publishes
    # as `nixosConfigurations`, so the hive and the published machine
    # are the same evaluation.
    colmenaHiveEvaluatesEndToEnd =
      let
        top = colmenaTop {
          probe-node = {
            imports = [ minimalNixosBase ];
            networking.hostName = "probe";
            deployment.targetHost = "probe";
          };
        };
        hive = top.colmenaHive;
        node = top.nixosConfigurations.probe-node;
      in
      hive.__schema == (inputs.colmena.lib.makeHive { }).__schema
      && hive.toplevel.probe-node.drvPath == node.config.system.build.toplevel.drvPath
      && hive.deploymentConfig.probe-node.targetHost == "probe"
      && hive.metaConfig.allowApplyAll == false
      && builtins.attrNames (hive.evalSelectedDrvPaths [ "probe-node" ]) == [ "probe-node" ];

    # A node is the NixOS configuration nixos.mkConfiguration builds from
    # the same module, with colmena's deployment options declared by
    # default: the deployment module leaves the system untouched. A
    # `targetHost` the node leaves unset is the node's name in the hive.
    colmenaNodesAreNixosConfigurations =
      let
        hostModule = {
          imports = [ minimalNixosBase ];
          networking.hostName = "probe";
        };
        top = colmenaTop { probe = hostModule; };
        node = top.colmenaHive.nodes.probe;
        system = hiveLib.caisson.nixos.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule = hostModule;
        };
      in
      node.config.system.build.toplevel.drvPath == system.config.system.build.toplevel.drvPath
      && node.options ? deployment
      && node.config.deployment.targetHost == null
      && top.colmenaHive.deploymentConfig.probe.targetHost == "probe"
      && node.pkgs.hello.drvPath == pkgs.hello.drvPath;

    # A node without colmena's deployment options is refused when the
    # hive reads it. A NixOS configuration that selects its modules
    # itself leaves out the deployment module.
    colmenaRefusesNodesWithoutDeployment =
      !(builtins.tryEval
        (colmenaTopWith { moduleImports = _modules: [ ]; } { plain = minimalNixosBase; })
        .colmenaHive.nodes.plain
      ).success;

    # Node names colmena's flat hive reserved (meta, defaults, network)
    # are ordinary names here. A node is an evaluated NixOS
    # configuration, so its module takes its host name from its
    # definitions rather than from a `name` argument.
    colmenaNodesAreNamedFreely =
      let
        hive =
          (colmenaTop (
            builtins.mapAttrs
              (hostName: peer: {
                imports = [ minimalNixosBase ];
                networking.hostName = hostName;
                deployment.targetHost = peer;
                deployment.tags = [ peer ];
              })
              {
                meta = "defaults";
                defaults = "network";
                network = "meta";
              }
          )).colmenaHive;
      in
      builtins.attrNames hive.deploymentConfig == [
        "defaults"
        "meta"
        "network"
      ]
      && hive.deploymentConfig.meta.targetHost == "defaults"
      && hive.nodes.network.config.networking.hostName == "network"
      && builtins.attrNames (hive.evalSelected [ "meta" ]) == [ "meta" ];

    # Names colmena's `--on` filter cannot express are refused at hive
    # evaluation.
    colmenaRefusesUnaddressableNames =
      let
        refused =
          nodeName:
          !(builtins.tryEval (colmenaTop { ${nodeName} = minimalNixosBase; }).colmenaHive.nodes).success;
      in
      refused "a,b" && refused "@tagged" && refused "";

    # A node is one evaluation. A NixOS configuration inside a colmena
    # configuration that puts two systems in force is evaluated per
    # system, once for each, and the hive refuses it. The top still publishes both
    # evaluations as NixOS configurations, and each evaluates, so it is
    # the hive that refuses them. With one system in force the same
    # tree has one node.
    colmenaRefusesNodesEvaluatedMoreThanOnce =
      let
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        twoSystemsLib = core.mkLib {
          sources = { };
          inherit systems;
          projects.caisson = inputs.caisson;
          defaultEcosystemSrc = {
            inherit (inputs) nixpkgs colmena;
          };
          pkgSets = _lib: {
            default =
              { name, parent }:
              {
                _type = "caisson-manifest";
                type = "nixpkgs";
                inherit name parent;
                children.nixpkgs = pkgs.lib.genAttrs systems (system: {
                  _type = "caisson-manifest";
                  type = "nixpkgs";
                  name = system;
                  value = import inputs.nixpkgs { inherit system; };
                });
              };
          };
        };
        topAt =
          inForce:
          twoSystemsLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.forChildren.systems = inForce;
                      caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                        configModule = minimalNixosBase;
                      };
                    };
                };
              };
          };
        both = topAt systems;
        one = topAt [ "x86_64-linux" ];
      in
      builtins.attrNames both.nixosConfigurations == [
        "aarch64-linux/probe"
        "x86_64-linux/probe"
      ]
      && both.nixosConfigurations."aarch64-linux/probe".pkgs.stdenv.hostPlatform.system == "aarch64-linux"
      && both.nixosConfigurations."x86_64-linux/probe".pkgs.stdenv.hostPlatform.system == "x86_64-linux"
      && !(builtins.tryEval (builtins.attrNames both.colmenaHive.nodes)).success
      && builtins.attrNames one.colmenaHive.nodes == [ "probe" ];

    # colmena's command refuses a hive whose schema version it does not
    # read. The hive asserts its schema against the schema of the
    # `makeHive` of the colmena source it is evaluated with, so a colmena
    # whose schema has moved refuses the hive when it is evaluated. The
    # colmena here is the pinned colmena with the schema of its
    # `makeHive` changed.
    colmenaRefusesAColmenaWithAnotherSchema =
      let
        movedSchema = inputs.colmena // {
          lib = inputs.colmena.lib // {
            makeHive = hive: inputs.colmena.lib.makeHive hive // { __schema = "v0.0"; };
          };
        };
        topWith =
          ecosystemSrc:
          hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                  inherit ecosystemSrc;
                  configModule =
                    { lib, ... }:
                    {
                      caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                        configModule = minimalNixosBase;
                      };
                    };
                };
              };
          };
      in
      (topWith inputs.colmena).colmenaHive.__schema == (inputs.colmena.lib.makeHive { }).__schema
      && !(builtins.tryEval (topWith movedSchema).colmenaHive).success;

    # `colmena eval` calls the hive's `introspect` with a function of
    # `{ lib, pkgs, nodes }`. The hive hands it the composed library,
    # the package set passed as `pkgSets.pkgs`, and the nodes. A hive
    # given no package set still hands over the library and the nodes,
    # and refuses when the function reads `pkgs`.
    colmenaIntrospectHandsOverTheNodes =
      let
        probe = {
          imports = [ minimalNixosBase ];
          networking.hostName = "probe";
        };
        withPkgs = (colmenaTop { inherit probe; }).colmenaHive;
        withoutPkgs =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                        configModule = probe;
                      };
                    };
                };
              };
          }).colmenaHive;
        read =
          {
            lib,
            pkgs,
            nodes,
          }:
          {
            composed = lib ? caisson-core;
            hello = pkgs.hello.drvPath;
            hostNames = builtins.mapAttrs (_: node: node.config.networking.hostName) nodes;
          };
        readNodes = { lib, nodes, ... }: lib ? caisson-core && builtins.attrNames nodes == [ "probe" ];
        readPkgs = { pkgs, ... }: pkgs.hello.drvPath;
      in
      withPkgs.introspect read == {
        composed = true;
        hello = pkgs.hello.drvPath;
        hostNames.probe = "probe";
      }
      && withoutPkgs.introspect readNodes
      && !(builtins.tryEval (withoutPkgs.introspect readPkgs)).success;

    # A structural configuration groups NixOS configurations so the
    # group can be declared wherever machines are, as a unit. The same
    # group of two machines is declared under a structural top and
    # inside a colmena configuration: each machine is the same
    # evaluation in both places, the top publishes the machines under
    # their own names, and the colmena configuration finds its nodes
    # through the group, under the same names.
    structuralGroupsNixosConfigurationsForReuse =
      let
        group =
          lib:
          lib.caisson.structural.mkConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations = lib.genAttrs [ "host-1" "host-2" ] (
                  hostName:
                  lib.caisson.nixos.mkConfiguration {
                    configModule = {
                      imports = [ minimalNixosBase ];
                      networking.hostName = hostName;
                    };
                  }
                );
              };
          };
        plain = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.structural.configurations.machines = group lib;
            };
        };
        deployed = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.structural.configurations.machines = group lib;
                  };
              };
            };
        };
        drvOf = machine: machine.config.system.build.toplevel.drvPath;
        hive = deployed.colmenaHive;
      in
      builtins.attrNames plain.nixosConfigurations == [
        "host-1"
        "host-2"
      ]
      &&
        builtins.attrNames hive.nodes == [
          "host-1"
          "host-2"
        ]
      && drvOf plain.nixosConfigurations.host-1 == drvOf hive.nodes.host-1
      && hive.nodes.host-2.config.networking.hostName == "host-2"
      && hive.deploymentConfig.host-1.targetHost == "host-1"
      && drvOf deployed.nixosConfigurations.host-2 == drvOf hive.nodes.host-2;

    # Structural configurations inside a colmena configuration group its
    # machines, and each group gives its machines its own modules, which
    # is what colmena's `defaults` and per-node modules are for. Two
    # groups add different modules to the default of the NixOS
    # configurations beneath them: hosts a, b and c get the first, d and
    # e the second. Each module also tags its machines with the name of
    # the group, so `colmena apply --on @first` selects the first group.
    # Every node gets the module and the tag of its own group and not
    # the other, and every machine is a node of the hive.
    structuralGroupsInsideColmenaGiveTheirMachinesModules =
      let
        groupModule = groupName: {
          environment.etc.group-name.text = groupName;
          deployment.tags = [ groupName ];
        };
        group =
          lib: groupName: hostNames:
          lib.caisson.structural.mkConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [ (groupModule groupName) ];
                caisson.nixos.configurations = lib.genAttrs hostNames (
                  hostName:
                  lib.caisson.nixos.mkConfiguration {
                    configModule = {
                      imports = [ minimalNixosBase ];
                      networking.hostName = hostName;
                    };
                  }
                );
              };
          };
        hive =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.structural.configurations = {
                        first = group lib "first" [
                          "a"
                          "b"
                          "c"
                        ];
                        second = group lib "second" [
                          "d"
                          "e"
                        ];
                      };
                    };
                };
              };
          }).colmenaHive;
        hosts = [
          "a"
          "b"
          "c"
          "d"
          "e"
        ];
        groupOf = host: hive.nodes.${host}.config.environment.etc.group-name.text;
        tagged = tag: builtins.filter (host: builtins.elem tag hive.deploymentConfig.${host}.tags) hosts;
      in
      builtins.attrNames hive.nodes == hosts
      &&
        builtins.map groupOf hosts == [
          "first"
          "first"
          "first"
          "second"
          "second"
        ]
      &&
        tagged "first" == [
          "a"
          "b"
          "c"
        ]
      &&
        tagged "second" == [
          "d"
          "e"
        ];

    # The upstream-compatible colmena integration takes a hive in the
    # format colmena reads. Each node is a caisson NixOS configuration
    # built as colmena builds it: the `defaults` of the hive and the
    # modules of the node, with `name`, `nodes`, `meta.specialArgs` and
    # `meta.nodeSpecialArgs` as special arguments, running on
    # `meta.nixpkgs`, and `deployment.targetHost` defaulting to the
    # name of the node. A node reads another through `nodes`, and the
    # top publishes the nodes as NixOS configurations.
    colmenaUpstreamHiveEvaluates =
      let
        top = upstreamHiveTop;
        hive = top.colmenaHive;
        etc = node: hive.nodes.${node}.config.environment.etc;
      in
      builtins.attrNames hive.nodes == [
        "alpha"
        "beta"
      ]
      && (etc "alpha").shared.text == "everywhere"
      && (etc "alpha").peer.text == "beta"
      && (etc "beta").only.text == "beta"
      && hive.nodes.alpha.config.deployment.targetHost == "alpha"
      && hive.deploymentConfig.beta.targetHost == "beta"
      && hive.metaConfig.allowApplyAll == false
      && hive.nodes.alpha.pkgs.hello.drvPath == pkgs.hello.drvPath
      && top.nixosConfigurations.beta.config.networking.hostName == "beta";

    # A node of the upstream-compatible integration builds the same
    # system as colmena builds from the same hive.
    colmenaUpstreamHiveBuildsWhatColmenaBuilds =
      let
        upstream = inputs.colmena.lib.makeHive upstreamHive;
        hive = upstreamHiveTop.colmenaHive;
      in
      hive.toplevel.alpha.drvPath == upstream.toplevel.alpha.drvPath
      && hive.toplevel.beta.drvPath == upstream.toplevel.beta.drvPath;

    # `colmenaHive` holds a single value, so only a colmena
    # configuration declared under the name `default` is published
    # there.
    colmenaHiveIsTheDefaultConfiguration =
      !(builtins.tryEval
        (hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.other = lib.caisson.caisson-colmena.mkConfiguration { };
            };
        }).colmenaHive
      ).success;

    # A machine installed onto a caisson-disko layout gets the file
    # systems, boot settings and swap the layout produces, and nothing
    # of disko: it has no `disko` option and no disko scripts. It is
    # the system NixOS builds from disko's own module and the same
    # layout. The machine `nas-1` inside the layout `nas-1` is published
    # as `nixosConfigurations.nas-1`, beside `diskoConfigurations.nas-1`.
    caissonDiskoMachinesGetTheLayoutsSettings =
      let
        top = layoutTop {
          integration = "caisson-disko";
          layout = luksLvmLayout;
          machine = diskoMachineBase;
        };
        machine = top.nixosConfigurations.nas-1;
        upstream = upstreamDiskoMachine luksLvmLayout;
      in
      builtins.attrNames top.nixosConfigurations == [ "nas-1" ]
      && builtins.attrNames top.diskoConfigurations == [ "nas-1" ]
      && !(machine.options ? disko)
      && !(machine.config.system.build ? formatScript)
      && machine.config.fileSystems."/".device == upstream.config.fileSystems."/".device
      && machine.config.system.build.toplevel.drvPath == upstream.config.system.build.toplevel.drvPath;

    # A caisson-disko layout is published in the form disko's command
    # reads. disko's own evaluator, given the published layout, makes
    # the format script it makes from the layout as written, and the
    # layout's own `scripts` output is that script too.
    caissonDiskoPublishesWhatDiskosCommandReads =
      let
        top = layoutTop {
          integration = "caisson-disko";
          layout = complexLayout;
        };
        upstream = import inputs.disko { inherit (pkgs) lib; };
        formatOf = layout: (upstream._cliFormat layout pkgs).drvPath;
        outputs = (layoutManifest "caisson-disko" top).outputs;
      in
      formatOf top.diskoConfigurations.nas-1 == formatOf complexLayout
      && (outputs.scripts pkgs).format.drvPath == formatOf complexLayout
      && outputs.nixosConfig ? fileSystems
      && builtins.isString outputs.layoutHash;

    # A layout with no machine installed onto it is published as a
    # layout and nothing else.
    caissonDiskoLayoutsNeedNoMachine =
      let
        top = layoutTop {
          integration = "caisson-disko";
          layout = luksLvmLayout;
        };
      in
      builtins.attrNames top.diskoConfigurations == [ "nas-1" ] && !(top ? nixosConfigurations);

    # A module of the caisson-disko class refuses a layout with an
    # assertion, and then every output of the layout fails.
    caissonDiskoAssertionsRefuseALayout =
      let
        top = layoutTop {
          integration = "caisson-disko";
          layout = {
            imports = [ luksLvmLayout ];
            assertions = [
              {
                assertion = false;
                message = "the probe refuses every layout";
              }
            ];
          };
          machine = diskoMachineBase;
        };
        fails = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      fails top.diskoConfigurations.nas-1 && fails top.nixosConfigurations.nas-1.config.fileSystems;

    # A disko configuration is a layout on its own, as disko's
    # standalone form has it. It is published as
    # `diskoConfigurations.nas-1`, with no machine beside it, and both
    # disko's evaluator given the published layout and the layout's own
    # `scripts` output make the format script disko makes from the
    # layout as written.
    diskoLayoutsStandAlone =
      let
        top = layoutTop {
          integration = "disko";
          layout = complexLayout;
        };
        upstream = import inputs.disko { inherit (pkgs) lib; };
        formatOf = layout: (upstream._cliFormat layout pkgs).drvPath;
        outputs = (layoutManifest "disko" top).outputs;
      in
      builtins.attrNames top.diskoConfigurations == [ "nas-1" ]
      && !(top ? nixosConfigurations)
      && formatOf top.diskoConfigurations.nas-1 == formatOf complexLayout
      && (outputs.scripts pkgs).format.drvPath == formatOf complexLayout;

    # disko's NixOS form: a NixOS configuration that selects caisson's
    # `disko` NixOS module and writes its layout as `disko.devices`. It
    # is what disko's tools read, the scripts under `system.build` and
    # `config.disko.devices`, and it is the system NixOS builds from
    # disko's module and the same layout, with the same format script.
    # `disko-install` replaces the disks with `extendModules` and
    # `mkVMOverride`, and the replacement holds.
    diskosNixosFormIsANixosConfiguration =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                extraModuleImports = modules: [ modules."caisson/disko" ];
                configModule = {
                  imports = [
                    luksLvmLayout
                    diskoMachineBase
                  ];
                };
              };
            };
        };
        machine = top.nixosConfigurations.nas-1;
        upstream = upstreamDiskoMachine luksLvmLayout;
        installed = machine.extendModules {
          modules = [
            (
              { lib, ... }:
              {
                disko.devices.disk.main = lib.mkVMOverride {
                  device = "/dev/vdz";
                  type = "disk";
                };
              }
            )
          ];
        };
      in
      builtins.attrNames top.nixosConfigurations == [ "nas-1" ]
      && !(top ? diskoConfigurations)
      && machine.config.disko.devices.disk ? main
      && machine.config.system.build.toplevel.drvPath == upstream.config.system.build.toplevel.drvPath
      &&
        machine.config.system.build.formatScript.drvPath
        == upstream.config.system.build.formatScript.drvPath
      && installed.config.disko.devices.disk.main.device == "/dev/vdz";

    # disko's install test extends a NixOS configuration that imports
    # the NixOS module of disko. A NixOS configuration that selects
    # caisson's `disko` NixOS module builds the install test that the
    # machine NixOS builds from disko's module and the same layout
    # builds.
    #
    # disko's image builder, `diskoImages` and `diskoImagesScript`, fails
    # to evaluate at the pinned disko and nixpkgs on a machine with no
    # caisson: disko passes `vmTools` a tree of kernel modules as its
    # `kernel`, which `vmTools` refuses. The test covers the install
    # test alone.
    diskosNixosFormBuildsDiskosInstallTest =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                extraModuleImports = modules: [ modules."caisson/disko" ];
                configModule = {
                  imports = [
                    luksLvmLayout
                    diskoMachineBase
                  ];
                };
              };
            };
        };
        build = top.nixosConfigurations.nas-1.config.system.build;
        upstream = (upstreamDiskoMachine luksLvmLayout).config.system.build;
      in
      build.installTest.drvPath == upstream.installTest.drvPath;

    # The mount point of a layout is the directory its scripts mount it
    # under, "/mnt" when the layout passes none. A layout of either disko
    # integration that passes `rootMountPoint` has the mount script disko
    # makes from the layout as written for that directory, and records
    # the directory in its outputs.
    diskoLayoutsMountUnderTheirRootMountPoint =
      let
        mountOf =
          rootMountPoint:
          (
            (import inputs.disko {
              inherit (pkgs) lib;
              inherit rootMountPoint;
            })._cliMount
              complexLayout
              pkgs
          ).drvPath;
        outputsOf =
          integration: args:
          (layoutManifest integration (layoutTop {
            inherit integration args;
            layout = complexLayout;
          })).outputs;
        mountsUnder =
          integration:
          let
            moved = outputsOf integration { rootMountPoint = "/target"; };
            unmoved = outputsOf integration { };
          in
          moved.rootMountPoint == "/target"
          && (moved.scripts pkgs).mount.drvPath == mountOf "/target"
          && unmoved.rootMountPoint == "/mnt"
          && (unmoved.scripts pkgs).mount.drvPath == mountOf "/mnt";
      in
      mountOf "/target" != mountOf "/mnt" && mountsUnder "caisson-disko" && mountsUnder "disko";

    # A caisson-disko layout can have several machines installed onto
    # it, such as a machine and its rescue system. Each is published
    # under the name it is declared with, and each gets the file
    # systems of the layout.
    caissonDiskoLayoutsHoldSeveralMachines =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ luksLvmLayout ];
                    caisson.nixos.configurations = lib.genAttrs [ "nas-1" "nas-1-rescue" ] (
                      _hostName: lib.caisson.nixos.mkConfiguration { configModule = diskoMachineBase; }
                    );
                  };
              };
            };
        };
        upstream = upstreamDiskoMachine luksLvmLayout;
        rootOf = machine: machine.config.fileSystems."/".device;
      in
      builtins.attrNames top.nixosConfigurations == [
        "nas-1"
        "nas-1-rescue"
      ]
      && builtins.attrNames top.diskoConfigurations == [ "nas-1" ]
      && rootOf top.nixosConfigurations.nas-1 == rootOf upstream
      && rootOf top.nixosConfigurations.nas-1-rescue == rootOf upstream
      && top.nixosConfigurations.nas-1-rescue.config.networking.hostName == "nas-1-rescue";

    # A layout declared inside a colmena configuration passes up the
    # machine installed onto it, so the machine `nas-1` is the node
    # `nas-1` of the hive, and the top publishes it as
    # `nixosConfigurations.nas-1` beside `diskoConfigurations.nas-1`.
    diskoLayoutsInsideColmenaAreNodes =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.default = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ luksLvmLayout ];
                          caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                            configModule = diskoMachineBase // {
                              networking.hostName = "nas-1";
                            };
                          };
                        };
                    };
                  };
              };
            };
        };
        hive = top.colmenaHive;
      in
      builtins.attrNames hive.nodes == [ "nas-1" ]
      && hive.deploymentConfig.nas-1.targetHost == "nas-1"
      && builtins.attrNames top.nixosConfigurations == [ "nas-1" ]
      && builtins.attrNames top.diskoConfigurations == [ "nas-1" ]
      &&
        hive.toplevel.nas-1.drvPath == top.nixosConfigurations.nas-1.config.system.build.toplevel.drvPath;

    # The convention for a machine inside a layout: the layout declares
    # it under the layout's own name, read from
    # `lib.caisson-core.evalManifest.name`, and caisson's default NixOS
    # module names the host after the name the machine is declared
    # under. A machine that sets its own host name keeps it.
    diskoMachinesNamedAfterTheirLayout =
      let
        layoutWith =
          machine:
          hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ luksLvmLayout ];
                      caisson.nixos.configurations.${lib.caisson-core.evalManifest.name} =
                        lib.caisson.nixos.mkConfiguration
                          { configModule = machine; };
                    };
                };
              };
          };
        named = layoutWith diskoMachineBase;
        renamed = layoutWith (diskoMachineBase // { networking.hostName = "storage"; });
      in
      builtins.attrNames named.nixosConfigurations == [ "nas-1" ]
      && named.nixosConfigurations.nas-1.config.networking.hostName == "nas-1"
      && renamed.nixosConfigurations.nas-1.config.networking.hostName == "storage";

    # A darwin configuration evaluates for aarch64-darwin on any host, and
    # builds the system nix-darwin's `darwinSystem` builds from the same
    # module and the same package set. It is published as
    # `darwinConfigurations.<name>` with `system` beside `config`, which
    # is what `darwin-rebuild` reads, and it runs on the package set the
    # composition declares. nix-darwin records no nixpkgs revision for a
    # package set it did not build, with caisson as with `darwinSystem`.
    darwinBuildsWhatDarwinSystemBuilds =
      let
        probe = import ../darwin-system { inherit inputs; };
        upstream = inputs.nix-darwin.lib.darwinSystem {
          inherit (probe) pkgs;
          modules = [
            { nixpkgs.hostPlatform = probe.system; }
            probe.machine
          ];
        };
      in
      builtins.attrNames probe.top.darwinConfigurations == [
        "family"
        "probe"
      ]
      && probe.toplevel.drvPath == upstream.system.drvPath
      && probe.configuration.config.nixpkgs.hostPlatform.system == "aarch64-darwin"
      && probe.configuration.pkgs.hello.drvPath == probe.pkgs.hello.drvPath;

    # A home and a hjem configuration inside a darwin machine take the
    # home directory and the user ID from the account the machine
    # declares, and the machine activates both. Its `postActivation`
    # step runs the activation of the home as the user, as
    # home-manager's nix-darwin module does, and it installs hjem's
    # launchd agent in `/Library/LaunchAgents`, which applies a manifest
    # equal to the one hjem's nix-darwin module makes from the same user
    # module. The home is published as `probe@family`.
    darwinActivatesItsHomes =
      let
        probe = import ../darwin-system { inherit inputs; };
        config = probe.family.config;
        homeManifest = probe.familyManifest.children.system.${probe.system}.children.home-manager.probe;
        hjemManifest = probe.familyManifest.children.system.${probe.system}.children.hjem.probe;
        upstream = inputs.nix-darwin.lib.darwinSystem {
          inherit (probe) pkgs;
          modules = [
            { nixpkgs.hostPlatform = probe.system; }
            inputs.hjem.darwinModules.default
            probe.machine
            { hjem.users.probe = probe.hjemUser; }
          ];
        };
        hjemLib = import "${inputs.hjem}/lib.nix" {
          inherit (probe.pkgs) lib;
          inherit (probe) pkgs;
        };
        upstreamManifest = probe.lib.caisson.hjem.manifestOf hjemLib upstream.config.hjem.users.probe;
        postActivation = config.system.activationScripts.postActivation.text;
        hasInfix = probe.pkgs.lib.strings.hasInfix;
      in
      homeManifest.value.config.home.homeDirectory == "/Users/probe"
      && homeManifest.value.config.home.uid == 501
      && hasInfix "-activation-probe" postActivation
      && hasInfix "launchctl asuser" postActivation
      && hjemManifest.value.config.directory == "/Users/probe"
      && builtins.toJSON hjemManifest.outputs.manifest == builtins.toJSON upstreamManifest
      && config.launchd.agents.hjem-activate.serviceConfig.Label == "org.hjem.activate"
      && config.launchd.user.agents == { }
      && hasInfix "gui/\${uid}/org.hjem.activate" postActivation
      && builtins.elem "hello" (
        builtins.map (package: package.pname or "") config.users.users.probe.packages
      )
      && builtins.attrNames probe.top.homeConfigurations == [ "probe@family" ]
      && builtins.attrNames probe.top.hjemConfigurations == [ "probe" ];

    # nix-darwin leaves `users.users.<name>.home` at `null` until the
    # machine sets it. A darwin machine whose account for `probe` sets
    # no home directory refuses the home and the hjem configuration of
    # `probe` declared inside it, where the same machine with the home
    # directory set evaluates. A home or a hjem configuration that sets
    # its home directory itself is refused by an assertion of the
    # machine or of the hjem configuration, which names the user. An
    # account without `uid` is accepted, as home-manager's nix-darwin
    # module accepts it, and the home's `home.uid` stays unset.
    darwinRefusesAccountsWithoutAHomeDirectory =
      let
        probe = import ../darwin-system { inherit inputs; };
        hasInfix = probe.pkgs.lib.strings.hasInfix;
        fails = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
        familyWith =
          {
            account,
            home ? probe.home,
            hjemUser ? probe.hjemUser,
          }:
          let
            top = probe.lib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
                    configModule =
                      { lib, ... }:
                      {
                        imports = [ (probe.machine // { users.users.probe = account; }) ];
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
            inside =
              top.caisson.manifest.children.system.${probe.system}.children.darwin.family.children.system.${probe.system}.children;
          in
          {
            machine = top.darwinConfigurations.family.config;
            system = top.darwinConfigurations.family.system;
            home = inside.home-manager.probe.value.config;
            hjem = inside.hjem.probe.value.config;
            hjemManifest = builtins.toJSON inside.hjem.probe.outputs.manifest;
          };
        refuses =
          message: assertions:
          builtins.any (item: !item.assertion && hasInfix message item.message) assertions;
        complete = familyWith {
          account = {
            home = "/Users/probe";
            uid = 501;
          };
        };
        withoutHome = familyWith { account.uid = 501; };
        setByUser = familyWith {
          account.uid = 501;
          home = {
            imports = [ probe.home ];
            home.homeDirectory = "/Users/probe";
          };
          hjemUser = {
            imports = [ probe.hjemUser ];
            directory = "/Users/probe";
          };
        };
        withoutUid = familyWith { account.home = "/Users/probe"; };
      in
      !(fails complete.system.drvPath)
      && !(fails complete.hjemManifest)
      && fails withoutHome.system.drvPath
      && fails withoutHome.hjemManifest
      && refuses "sets no home directory" setByUser.machine.assertions
      && refuses "sets no home directory" setByUser.hjem.assertions
      && withoutUid.home.home.homeDirectory == "/Users/probe"
      && withoutUid.home.home.uid == null
      && withoutUid.hjem.directory == "/Users/probe";

    # A hjem configuration inside a darwin machine is for a user the
    # machine declares an account for. The machine here declares the
    # account `probe` and holds a hjem configuration for `guest`. The
    # hjem configuration has no home directory, so its manifest fails.
    # A hjem configuration for `guest` that sets its directory itself is
    # refused by an assertion that names the user.
    darwinRefusesHjemUsersWithoutAnAccount =
      let
        probe = import ../darwin-system { inherit inputs; };
        hasInfix = probe.pkgs.lib.strings.hasInfix;
        fails = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
        guestWith =
          hjemUser:
          (probe.lib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ probe.machine ];
                      caisson.hjem.configurations.guest = lib.caisson.hjem.mkConfiguration {
                        configModule = hjemUser;
                      };
                    };
                };
              };
          })
          .caisson.manifest.children.system.${probe.system}.children.darwin.family.children.system.${probe.system}.children.hjem.guest;
        unset = guestWith probe.hjemUser;
        set = guestWith {
          imports = [ probe.hjemUser ];
          directory = "/Users/guest";
        };
      in
      fails unset.outputs.manifest
      && builtins.any (
        item: !item.assertion && hasInfix "`guest` has no account" item.message
      ) set.value.config.assertions;

    # A darwin machine activates the profiles declared inside it in its
    # `postActivation` step: an nvf configuration declared in the
    # machine as root, and an nvf configuration declared inside the hjem
    # configuration of `probe` as that user, through `launchctl asuser`.
    # The machine installs the program with which a shell chooses the
    # profile of the system, and the hjem configuration chooses the
    # profile declared inside it for the shells of its user.
    darwinActivatesTheProfilesInsideIt =
      let
        probe = import ../darwin-system { inherit inputs; };
        hasInfix = probe.pkgs.lib.strings.hasInfix;
        nvfConfiguration =
          lib: module:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = inputs.nvf;
            configModule = module;
          };
        top = probe.lib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ probe.machine ];
                    caisson.nvf.configurations.editor = nvfConfiguration lib { vim.viAlias = true; };
                    caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ probe.hjemUser ];
                          caisson.nvf.configurations.hjem-editor = nvfConfiguration lib { vim.vimAlias = true; };
                        };
                    };
                  };
              };
            };
        };
        config = top.darwinConfigurations.family.config;
        inside =
          top.caisson.manifest.children.system.${probe.system}.children.darwin.family.children.system.${probe.system}.children;
        ofSystem = inside.nvf.editor.outputs;
        ofHjem = inside.hjem.probe.children.system.${probe.system}.children.nvf.hjem-editor.outputs;
        postActivation = config.system.activationScripts.postActivation.text;
        # The step refers to the activation package: the string context
        # of the script records it.
        runs =
          outputs:
          builtins.elem outputs.activationPackage.drvPath (
            builtins.attrNames (builtins.getContext postActivation)
          );
        names = packages: builtins.map (package: package.name or "") packages;
      in
      runs ofSystem
      && runs ofHjem
      && hasInfix "launchctl asuser" postActivation
      && hasInfix "sudo -u probe --set-home" postActivation
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (
        names config.environment.systemPackages
      )
      &&
        inside.hjem.probe.value.config.environment.sessionVariables.CAISSON_NVIM_PROFILE
        == "/Users/probe/.local/state/caisson/profiles/nvf/hjem-editor";

    # A hjem configuration that is a top gives what hjem's standalone
    # CLI reads from a file: the version 3 manifest of the user's files,
    # with targets in the user's home directory, and the packages. The
    # manifest of the evaluation sits under `caisson.manifest`, behind an
    # `outPath`, so the JSON the CLI reads holds a string in its place.
    hjemTopIsWhatHjemsCliReads =
      let
        probe = import ../hjem-system { inherit inputs; };
        top = probe.standalone;
        targets = builtins.map (file: file.target) top.manifest.files;
      in
      top.manifest.version == 3
      &&
        builtins.sort builtins.lessThan targets == [
          "/home/probe/.config/probe/greeting"
          "/home/probe/.config/probe/settings"
        ]
      && builtins.all (file: file.type == "symlink") top.manifest.files
      && builtins.map (package: package.pname) top.packages == [ "hello" ]
      && builtins.toJSON top.caisson == builtins.toJSON "caisson manifest: read caisson.manifest"
      && top.caisson.manifest.type == "hjem";

    # A hjem configuration with no machine above it, with an nvf
    # configuration inside it, carries in its files what activates the
    # profile when `hjem standalone switch` applies them: the systemd
    # user units `caisson-profiles` on Linux, and the launchd agent
    # `org.caisson.profiles` on macOS, which runs at load, watches the
    # manifest of the current generation, and runs the script the files
    # link at `~/.local/state/caisson/activate-profiles`. A hjem
    # configuration inside a machine carries neither, since the machine
    # activates its profiles.
    hjemStandaloneCarriesItsProfileActivation =
      let
        linux = import ../hjem-system { inherit inputs; };
        darwin = import ../darwin-system { inherit inputs; };
        targetsOf = manifest: builtins.map (file: file.target) manifest.files;
        withEditor =
          { lib, ... }:
          {
            caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
              ecosystemSrc = inputs.nvf;
              configModule.vim.viAlias = true;
            };
          };
        standalone = linux.lib.caisson.hjem.mkTopConfiguration {
          configModule = {
            imports = [
              linux.user
              withEditor
            ];
            user = "probe";
            directory = "/home/probe";
          };
        };
        inside =
          (linux.lib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations.probe-machine = lib.caisson.nixos.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ linux.machine ];
                      caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                        configModule = {
                          imports = [
                            linux.user
                            withEditor
                          ];
                        };
                      };
                    };
                };
              };
          })
          .caisson.manifest.children.system.${linux.system}.children.nixos.probe-machine.children.system.${linux.system}.children.hjem.probe;
        units = "/home/probe/.config/systemd/user";
        unitTargets = [
          "${units}/caisson-profiles.service"
          "${units}/default.target.wants/caisson-profiles.service"
          "${units}/caisson-profiles.path"
          "${units}/paths.target.wants/caisson-profiles.path"
        ];
        script = "/home/probe/.local/state/caisson/activate-profiles";
        agentTarget = "/Users/runner/Library/LaunchAgents/org.caisson.profiles.plist";
        hasInfix = linux.pkgs.lib.strings.hasInfix;
        # The text of the agent, as the derivation that writes it holds
        # it, so that the agent need not be built to be read.
        agentText =
          darwin.standaloneHjem.value.config.files."Library/LaunchAgents/org.caisson.profiles.plist".source.text;
        # The source of each file of a manifest, by target.
        sourcesOf =
          manifest:
          builtins.listToAttrs (
            builtins.map (file: {
              name = file.target;
              value = file.source;
            }) manifest.files
          );
        v1 = sourcesOf (darwin.standaloneHjemOf "v1").outputs.manifest;
        v2 = sourcesOf (darwin.standaloneHjemOf "v2").outputs.manifest;
        runnerScript = "/Users/runner/.local/state/caisson/activate-profiles";
      in
      builtins.all (target: builtins.elem target (targetsOf standalone.manifest)) (
        unitTargets ++ [ script ]
      )
      && !(builtins.any (target: builtins.elem target (targetsOf inside.outputs.manifest)) (
        unitTargets ++ [ script ]
      ))
      && !(builtins.elem agentTarget (targetsOf standalone.manifest))
      && builtins.elem agentTarget (targetsOf darwin.standaloneHjem.outputs.manifest)
      && hasInfix "/Users/runner/.local/state/hjem/standalone/current/manifest.json" agentText
      && hasInfix "<key>RunAtLoad</key>" agentText
      && hasInfix "<string>${runnerScript}</string>" agentText
      # systemd and launchd keep what they loaded until they load it
      # again, which a switch does not make them do. So the agent is the
      # same file in each version, and only the link to the script of
      # the version differs.
      && v1.${agentTarget} == v2.${agentTarget}
      && v1.${runnerScript} != v2.${runnerScript};

    # A hjem configuration inside a NixOS machine takes the home
    # directory of the account the machine declares, and its manifest is
    # the one hjem's own NixOS module makes from the same user module,
    # the systemd user unit of the user included. The machine activates
    # it with the template units hjem's NixOS module writes, which read
    # the manifest file from the directory of this generation, installs
    # the user's packages, and the top publishes it as
    # `hjemConfigurations.probe`.
    hjemInsideNixosIsActivated =
      let
        probe = import ../hjem-system { inherit inputs; };
        inner = probe.inner;
        machine = probe.top.nixosConfigurations.probe-machine;
        services = machine.config.systemd.services;
        upstream = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
          inherit (probe) system;
          modules = [
            inputs.hjem.nixosModules.default
            probe.machine
            { hjem.users.probe = probe.machineUser; }
          ];
        };
        hjemLib = import "${inputs.hjem}/lib.nix" {
          inherit (probe.pkgs) lib;
          inherit (probe) pkgs;
        };
        upstreamManifest = probe.lib.caisson.hjem.manifestOf hjemLib upstream.config.hjem.users.probe;
        targets = builtins.map (file: file.target) inner.outputs.manifest.files;
        target = machine.config.systemd.targets.hjem;
      in
      inner.value.config.directory == "/home/probe"
      && builtins.toJSON inner.outputs.manifest == builtins.toJSON upstreamManifest
      && builtins.elem "/home/probe/.config/systemd/user/probe.service" targets
      && builtins.all (name: services ? ${name}) [
        "hjem-prepare"
        "hjem-activate@"
        "hjem-reload@"
        "hjem-update-state@"
        "hjem-cleanup"
      ]
      && builtins.elem "hjem-activate@probe.service" target.requires
      && probe.pkgs.lib.strings.hasInfix "hjem-activate-step" services."hjem-activate@".script
      && builtins.elem "hello" (
        builtins.map (package: package.pname or "") machine.config.users.users.probe.packages
      )
      && builtins.attrNames probe.top.hjemConfigurations == [ "probe" ];

    # A machine inside a caisson-facter configuration and one inside a
    # facter configuration, from the report of nixpkgs' facter test, get
    # from nixpkgs' `hardware.facter` module what a NixOS configuration
    # that sets `hardware.facter.reportPath` itself gets: the same
    # report and the same kernel modules for the initrd. The
    # caisson-facter configuration refuses a report of a version it does
    # not know, and a hardware an assertion refuses.
    facterHandsTheReportToNixpkgs =
      let
        reportPath = "${inputs.nixpkgs}/nixos/tests/facter/facter.json";
        machine = {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.05";
        };
        upstream = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
          system = "x86_64-linux";
          modules = [
            machine
            { hardware.facter.reportPath = reportPath; }
          ];
        };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-facter.configurations.native = lib.caisson.caisson-facter.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    facter.reportPath = reportPath;
                    caisson.nixos.configurations.native = lib.caisson.nixos.mkConfiguration {
                      configModule = machine;
                    };
                  };
              };
              caisson.facter.configurations.upstream = lib.caisson.facter.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    inherit reportPath;
                    caisson.nixos.configurations.upstream = lib.caisson.nixos.mkConfiguration {
                      configModule = machine;
                    };
                  };
              };
            };
        };
        native = top.nixosConfigurations.native.config;
        compatible = top.nixosConfigurations.upstream.config;
        kernelModules = config: builtins.sort builtins.lessThan config.boot.initrd.availableKernelModules;
        hardwareOf =
          configModule:
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-facter.configurations.probe = lib.caisson.caisson-facter.mkConfiguration {
                  inherit configModule;
                };
              };
          }).caisson.manifest.children.caisson-facter.probe.outputs;
        throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      builtins.toJSON native.hardware.facter.report
      == builtins.toJSON upstream.config.hardware.facter.report
      && compatible.hardware.facter.reportPath == upstream.config.hardware.facter.reportPath
      && kernelModules upstream.config != [ ]
      && kernelModules native == kernelModules upstream.config
      && kernelModules compatible == kernelModules upstream.config
      &&
        builtins.attrNames top.nixosConfigurations == [
          "native"
          "upstream"
        ]
      && (hardwareOf { facter.reportPath = reportPath; }).report.version == 1
      && throws (hardwareOf { facter.report.version = 99; }).report
      &&
        throws
          (hardwareOf {
            facter.reportPath = reportPath;
            assertions = [
              {
                assertion = false;
                message = "refused";
              }
            ];
          }).hash;

    # A treefmt configuration declared under the name `default` is
    # published as `formatter.<system>`, and its wrapper is the
    # derivation treefmt-nix's own `mkWrapper` builds from the same
    # module on the same package set. Its outputs carry the
    # configuration file and the check over a source tree. In a tree
    # that knows its root, its check over the root is published as
    # `checks.<system>.treefmt`. A tree may declare treefmt
    # configurations under other names beside `default`.
    treefmtIsTheFormatterTreefmtNixBuilds =
      let
        module = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        };
        declares =
          { lib, ... }:
          {
            caisson.treefmt.configurations.default = lib.caisson.treefmt.mkConfiguration {
              ecosystemSrc = inputs.treefmt-nix;
              configModule = module;
            };
            caisson.treefmt.configurations.docs = lib.caisson.treefmt.mkConfiguration {
              ecosystemSrc = inputs.treefmt-nix;
              configModule = {
                projectRootFile = "book.toml";
                programs.nixfmt.enable = true;
              };
            };
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = declares;
        };
        root = {
          outPath = ./.;
        };
        rootedLib = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            inherit root;
            projects.caisson = inputs.caisson;
            defaultEcosystemSrc = {
              inherit (inputs) nixpkgs;
            };
          }
        );
        rooted = rootedLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = declares;
        };
        children = top.caisson.manifest.children.system.x86_64-linux.children.treefmt;
        evaluation = children.default;
        rootedEvaluation = rooted.caisson.manifest.children.system.x86_64-linux.children.treefmt.default;
        upstream = inputs.treefmt-nix.lib.mkWrapper pkgs module;
      in
      builtins.attrNames top.formatter == [ "x86_64-linux" ]
      && top.formatter.x86_64-linux.drvPath == upstream.drvPath
      && evaluation.outputs.programs ? nixfmt
      && builtins.isString evaluation.outputs.configFile.drvPath
      && builtins.isString (evaluation.outputs.check ./.).drvPath
      # The check is published in the tree that has a root, as the
      # check of `default` over it.
      && !(top ? checks)
      && builtins.attrNames rooted.checks == [ "x86_64-linux" ]
      && builtins.attrNames rooted.checks.x86_64-linux == [ "treefmt" ]
      && rooted.checks.x86_64-linux.treefmt.drvPath == (rootedEvaluation.outputs.check root).drvPath
      && rooted.formatter.x86_64-linux.drvPath == upstream.drvPath
      # The configuration `docs` is evaluated.
      && builtins.isString children.docs.outputs.wrapper.drvPath;

    # An nvf configuration is published as
    # `nvfConfigurations.<system>.<name>`, and its Neovim is the one
    # nvf's own `neovimConfiguration` builds
    # from the same module on the same package set. An nvf configuration
    # declared inside a NixOS machine or a home is published with the
    # others.
    nvfIsTheNeovimNvfBuilds =
      let
        module = {
          vim.viAlias = true;
          vim.lineNumberMode = "number";
        };
        nvfConfiguration =
          lib:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = inputs.nvf;
            configModule = module;
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nvf.configurations.editor = nvfConfiguration lib;
              caisson.nixos.configurations.workstation = lib.caisson.nixos.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    boot.loader.grub.enable = false;
                    fileSystems."/" = {
                      device = "none";
                      fsType = "tmpfs";
                    };
                    system.stateVersion = "25.05";
                    caisson.nvf.configurations.machine-editor = nvfConfiguration lib;
                  };
              };
              caisson.home-manager.configurations.alice = lib.caisson.home-manager.mkConfiguration {
                ecosystemSrc = inputs.home-manager;
                configModule =
                  { lib, ... }:
                  {
                    home.homeDirectory = "/home/alice";
                    home.stateVersion = "25.05";
                    caisson.nvf.configurations.home-editor = nvfConfiguration lib;
                  };
              };
            };
        };
        upstream =
          (inputs.nvf.lib.neovimConfiguration {
            inherit pkgs;
            modules = [ module ];
          }).neovim;
        machine = top.nixosConfigurations.workstation.config;
        home = top.homeConfigurations.alice.config;
        unit = machine.systemd.services.caisson-profile-nvf-machine-editor;
        names = packages: builtins.map (package: package.name or "") packages;
        topProfile = top.caisson.manifest.children.system.x86_64-linux.children.nvf.editor.outputs.profile;
        published = top.nvfConfigurations.x86_64-linux.editor;
      in
      # The configuration is published in the shape `neovimConfiguration`
      # returns.
      published.neovim.drvPath == upstream.drvPath
      && published.config.vim.viAlias
      && published.options ? vim
      &&
        builtins.attrNames top.nvfConfigurations.x86_64-linux == [
          "editor"
          "home-editor"
          "machine-editor"
        ]
      # The machine activates the profile of the system as root, at boot
      # and at a switch, and lets a shell choose it with `nvim`.
      && unit.wantedBy == [ "multi-user.target" ]
      && !(unit.serviceConfig ? User)
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (
        names machine.environment.systemPackages
      )
      # The home activates its own profile, after its files are linked,
      # and chooses it for its shells.
      && pkgs.lib.hasInfix "/activate" home.home.activation.caissonProfiles.data
      &&
        home.home.sessionVariables.CAISSON_NVIM_PROFILE
        == "$HOME/.local/state/caisson/profiles/nvf/home-editor"
      # The top's own profile is a profile of the user, and it points at
      # the Neovim nvf builds.
      && topProfile.scope == "user"
      && topProfile.path == "$HOME/.local/state/caisson/profiles/nvf/editor"
      && topProfile.package.drvPath == upstream.drvPath;

    # A nixvim configuration is published as
    # `nixvimConfigurations.<system>.<name>`, and its package is the one
    # nixvim's own `evalNixvim` builds from the same module on the same
    # package set.
    nixvimIsTheNeovimNixvimBuilds =
      let
        module = {
          opts.number = true;
          globals.mapleader = " ";
        };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixvim.configurations.editor = lib.caisson.nixvim.mkConfiguration {
                ecosystemSrc = inputs.nixvim;
                configModule = module;
              };
            };
        };
        upstream = inputs.nixvim.lib.evalNixvim {
          modules = [
            module
            { nixpkgs.pkgs = pkgs; }
          ];
        };
      in
      builtins.attrNames top.nixvimConfigurations == [ "x86_64-linux" ]
      &&
        top.nixvimConfigurations.x86_64-linux.editor.config.build.package.drvPath
        == upstream.config.build.package.drvPath;

    # A nixvim configuration declared inside a NixOS machine is a profile
    # of the system, as an nvf configuration there is. The machine writes
    # the unit that activates the profile as root, at boot and at a
    # switch, and installs the program with which a shell chooses the
    # profile. The unit runs `activate` of the activation package of the
    # profile, and the top publishes the configuration with the others.
    nixvimProfilesInsideAMachineAreActivated =
      let
        module = {
          opts.number = true;
        };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.workstation = lib.caisson.nixos.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ minimalNixosBase ];
                    caisson.nixvim.configurations.machine-editor = lib.caisson.nixvim.mkConfiguration {
                      ecosystemSrc = inputs.nixvim;
                      configModule = module;
                    };
                  };
              };
            };
        };
        upstream = inputs.nixvim.lib.evalNixvim {
          modules = [
            module
            { nixpkgs.pkgs = pkgs; }
          ];
        };
        machine = top.nixosConfigurations.workstation.config;
        unit = machine.systemd.services.caisson-profile-nixvim-machine-editor;
        profile =
          top.caisson.manifest.children.system.x86_64-linux.children.nixos.workstation.children.system.x86_64-linux.children.nixvim.machine-editor.outputs;
        names = packages: builtins.map (package: package.name or "") packages;
      in
      builtins.attrNames top.nixvimConfigurations.x86_64-linux == [ "machine-editor" ]
      && profile.package.drvPath == upstream.config.build.package.drvPath
      && profile.profile.scope == "system"
      && unit.wantedBy == [ "multi-user.target" ]
      && !(unit.serviceConfig ? User)
      && builtins.elem profile.activationPackage.drvPath (
        builtins.attrNames (builtins.getContext unit.serviceConfig.ExecStart)
      )
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (
        names machine.environment.systemPackages
      );

    # A topology configuration with two machines declared inside it reads
    # them as nix-topology reads NixOS configurations evaluated with its
    # NixOS module: the same nodes, and the same rendered diagram. It is
    # published as `topology.<system>` under the name `default`, and its
    # machines as `nixosConfigurations`.
    topologyReadsTheMachinesDeclaredInside =
      let
        machine = {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.05";
        };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.topology.configurations.default = lib.caisson.topology.mkConfiguration {
                ecosystemSrc = inputs.nix-topology;
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.alpha = lib.caisson.nixos.mkConfiguration {
                      configModule = machine;
                    };
                    caisson.nixos.configurations.beta = lib.caisson.nixos.mkConfiguration {
                      configModule = machine;
                    };
                  };
              };
            };
        };
        upstreamMachine =
          hostName:
          import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
            system = "x86_64-linux";
            modules = [
              machine
              "${inputs.nix-topology}/nixos/module.nix"
              { networking.hostName = hostName; }
            ];
          };
        upstream = import inputs.nix-topology {
          pkgs = pkgs.extend (import "${inputs.nix-topology}/pkgs/default.nix");
          modules = [
            {
              nixosConfigurations = {
                alpha = upstreamMachine "alpha";
                beta = upstreamMachine "beta";
              };
            }
          ];
        };
        topology = top.topology.x86_64-linux;
      in
      builtins.attrNames top.nixosConfigurations == [
        "alpha"
        "beta"
      ]
      && builtins.attrNames topology.config.nodes == builtins.attrNames upstream.config.nodes
      && builtins.elem "alpha" (builtins.attrNames topology.config.nodes)
      && topology.config.output.drvPath == upstream.config.output.drvPath;

    # A kubenix configuration is published as
    # `kubenixConfigurations.<system>.<name>`, its evaluation, whose
    # result is the result kubenix's own `evalModules` gives the same
    # module on the same package set.
    kubenixIsTheResultKubenixBuilds =
      let
        module =
          { kubenix, ... }:
          {
            imports = [ kubenix.modules.k8s ];
            kubernetes.resources.configMaps.demo.data.greeting = "hello";
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.kubenix.configurations.cluster = lib.caisson.kubenix.mkConfiguration {
                ecosystemSrc = inputs.kubenix;
                configModule = module;
              };
            };
        };
        upstream = import "${inputs.kubenix}/lib/eval-modules.nix" { inherit pkgs; } { inherit module; };
      in
      top.kubenixConfigurations.x86_64-linux.cluster.config.kubernetes.result.drvPath
      == upstream.config.kubernetes.result.drvPath;

    # A nixidy configuration is published as
    # `nixidyEnvs.<system>.<name>`, and its rendered environment is the
    # one nixidy's own `mkEnv` renders from the same module on the same
    # package set.
    nixidyIsTheEnvironmentNixidyRenders =
      let
        module = {
          nixidy.target.repository = "https://example.com/manifests.git";
          nixidy.target.branch = "main";
          applications.demo = {
            namespace = "demo";
            resources.configMaps.demo.data.greeting = "hello";
          };
        };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixidy.configurations.prod = lib.caisson.nixidy.mkConfiguration {
                ecosystemSrc = inputs.nixidy;
                configModule = module;
              };
            };
        };
        upstream = inputs.nixidy.lib.mkEnv {
          inherit pkgs;
          modules = [ module ];
        };
      in
      top.nixidyEnvs.x86_64-linux.prod.environmentPackage.drvPath == upstream.environmentPackage.drvPath;

    # A machine activates the profile inside a hjem configuration as the
    # user of that hjem configuration and of no other. The machine here
    # holds hjem configurations for `alice` and `bob` and a home for
    # `carol`, each with a profile inside it, and a profile of the
    # system. The configurations inside the machine are at the same
    # depth, so a machine that matched a profile to the configuration
    # above it by depth would activate each profile for every user. The
    # machine writes a unit for the profile of the system, and a unit
    # for the profile of each hjem user, as that user; the home activates its
    # profile itself.
    profilesBelongToTheConfigurationAboveThem =
      let
        probe = import ../hjem-system { inherit inputs; };
        editor =
          lib:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = inputs.nvf;
            configModule.vim.viAlias = true;
          };
        withEditor =
          name:
          { lib, ... }:
          {
            caisson.nvf.configurations.${name} = editor lib;
          };
        top = probe.lib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.probe-machine = lib.caisson.nixos.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ probe.machine ];
                    users.users.alice.isNormalUser = true;
                    users.users.bob.isNormalUser = true;
                    users.users.carol.isNormalUser = true;
                    caisson.profiles.selected.CAISSON_NVIM_PROFILE = "nvf/system-editor";
                    caisson.nvf.configurations.system-editor = editor lib;
                    caisson.hjem.configurations = {
                      alice = lib.caisson.hjem.mkConfiguration { configModule = withEditor "alice-editor"; };
                      bob = lib.caisson.hjem.mkConfiguration { configModule = withEditor "bob-editor"; };
                    };
                    caisson.home-manager.configurations.carol = lib.caisson.home-manager.mkConfiguration {
                      ecosystemSrc = inputs.home-manager;
                      configModule = {
                        imports = [ (withEditor "carol-editor") ];
                        home.stateVersion = "25.05";
                      };
                    };
                  };
              };
            };
        };
        services = top.nixosConfigurations.probe-machine.config.systemd.services;
        profileUnits = builtins.filter (name: probe.pkgs.lib.hasPrefix "caisson-profile-" name) (
          builtins.attrNames services
        );
      in
      profileUnits == [
        "caisson-profile-alice-nvf-alice-editor"
        "caisson-profile-bob-nvf-bob-editor"
        "caisson-profile-nvf-system-editor"
      ]
      && services.caisson-profile-alice-nvf-alice-editor.serviceConfig.User == "alice"
      && services.caisson-profile-bob-nvf-bob-editor.serviceConfig.User == "bob";

    # A system-manager machine activates the home, the hjem configuration
    # and the nvf configurations declared inside it, as a NixOS machine
    # does: the home and the hjem configuration take their directory from
    # the account the machine declares, the machine writes the units that
    # activate them and the profiles, installs the packages of the hjem
    # user, and the home is published as `probe@box`.
    systemManagerActivatesWhatIsDeclaredInside =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.system-manager.configurations.box = lib.caisson.system-manager.mkConfiguration {
                ecosystemSrc = inputs.system-manager;
                configModule =
                  { lib, ... }:
                  {
                    system-manager.allowAnyDistro = true;
                    users.groups.probe.gid = 5000;
                    users.users.probe = {
                      isNormalUser = true;
                      uid = 5000;
                      group = "probe";
                      home = "/home/probe";
                    };
                    caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration {
                      ecosystemSrc = inputs.home-manager;
                      configModule.home.stateVersion = "25.05";
                    };
                    caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                      ecosystemSrc = inputs.hjem;
                      configModule =
                        { lib, pkgs, ... }:
                        {
                          files.".config/probe/greeting".text = "hello";
                          packages = [ pkgs.hello ];
                          caisson.nvf.configurations.hjem-editor = lib.caisson.nvf.mkConfiguration {
                            ecosystemSrc = inputs.nvf;
                            configModule.vim.vimAlias = true;
                          };
                        };
                    };
                    caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
                      ecosystemSrc = inputs.nvf;
                      configModule.vim.viAlias = true;
                    };
                  };
              };
            };
        };
        box = top.systemConfigs.box.config;
        children =
          top.caisson.manifest.children.system.x86_64-linux.children.system-manager.box.children.system.x86_64-linux.children;
        home = children.home-manager.probe.value.config;
        hjem = children.hjem.probe.value.config;
        names = packages: builtins.map (package: package.name or "") packages;
        systemUnit = box.systemd.services.caisson-profile-nvf-editor;
        hjemUnit = box.systemd.services."hjem-activate@probe";
        hjemProfile =
          children.hjem.probe.children.system.x86_64-linux.children.nvf.hjem-editor.outputs.activationPackage;
      in
      home.home.homeDirectory == "/home/probe"
      # The machine records what it applied, and the home compares
      # against it when activated by hand, as inside a NixOS machine.
      && box.environment.etc ? "caisson/marker.json"
      && pkgs.lib.hasInfix "/etc/caisson/marker.json" home.home.activation.caissonDrift.data
      && hjem.directory == "/home/probe"
      && box.systemd.services ? home-manager-probe
      # system-manager cannot reload a template and restarts each changed
      # unit apart, so a single unit for the user runs the steps of hjem
      # in order, and then activates the profile inside the hjem
      # configuration.
      && !(box.systemd.services ? "hjem-activate@")
      && !(box.systemd.services ? "hjem-reload@probe")
      && !(box.systemd.services ? "hjem-update-state@probe")
      && !(box.systemd.services ? caisson-profile-probe-nvf-hjem-editor)
      && builtins.elem hjemProfile.drvPath (builtins.attrNames (builtins.getContext hjemUnit.script))
      # The machine activates its profile of the system as root; hjem
      # chooses the profile of the user.
      && systemUnit.wantedBy == [ "multi-user.target" ]
      && !(systemUnit.serviceConfig ? User)
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (names box.environment.systemPackages)
      &&
        hjem.environment.sessionVariables.CAISSON_NVIM_PROFILE
        == "/home/probe/.local/state/caisson/profiles/nvf/hjem-editor"
      && builtins.elem pkgs.hello.name (names box.users.users.probe.packages)
      && builtins.attrNames top.homeConfigurations == [ "probe@box" ];

    # A terranix configuration that is a top is its `config.tf.json`
    # file, built from the package set of the composition with the
    # evaluated configuration in its `passthru`, and its modules get the
    # composed library. Declared under a structural top, it is published
    # as `terranixConfigurations.<name>`.
    terranixConfigurationEvaluatesEndToEnd =
      let
        module =
          { lib, ... }:
          {
            config.terraform.required_version = ">= 1.0";
            config.output.composed.value = lib ? caisson-core;
          };
        terraform = hiveLib.caisson.terranix.mkTopConfiguration {
          ecosystemSrc = inputs.terranix;
          configModule = module;
        };
        published = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.terranix.configurations.infra = lib.caisson.terranix.mkConfiguration {
                ecosystemSrc = inputs.terranix;
                configModule = module;
              };
            };
        };
      in
      builtins.isString terraform.drvPath
      && terraform.name == "config.tf.json"
      && terraform.passthru.config.terraform.required_version == ">= 1.0"
      && terraform.passthru.config.output.composed.value
      && published.terranixConfigurations.infra.drvPath == terraform.drvPath;

    # A system-manager configuration that is a top is its system, built
    # for the system of the evaluation, and its modules get the composed
    # library. It runs on the package set caisson selects, the set named
    # `default`, and its userborn is built on that set. A configuration
    # that sets `nixpkgs.overlays`, which that set leaves without effect,
    # is refused. Declared under a structural top under the name
    # `default`, it is published as `systemConfigs.default`, which
    # `system-manager switch --flake` reads when no name is given.
    systemManagerConfigEvaluatesEndToEnd =
      let
        module =
          { lib, ... }:
          {
            config.system-manager.allowAnyDistro = true;
            config.environment.etc.composed.text = builtins.toJSON (lib ? caisson-core);
          };
        system = hiveLib.caisson.system-manager.mkTopConfiguration {
          ecosystemSrc = inputs.system-manager;
          configModule = module;
        };
        withOverlay = hiveLib.caisson.system-manager.mkTopConfiguration {
          ecosystemSrc = inputs.system-manager;
          configModule = {
            imports = [ module ];
            nixpkgs.overlays = [ (_final: _prev: { }) ];
          };
        };
        runsOn = system.config.nixpkgs.pkgs;
        userborn =
          (import "${inputs.system-manager.inputs.userborn}/nix/packages" { inherit pkgs; }).userborn;
        published = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.system-manager.configurations.default = lib.caisson.system-manager.mkConfiguration {
                ecosystemSrc = inputs.system-manager;
                configModule = module;
              };
            };
        };
      in
      builtins.isString system.drvPath
      && (
        let
          platform = system.config.nixpkgs.hostPlatform;
        in
        (if builtins.isString platform then platform else platform.system) == "x86_64-linux"
      )
      && system.config.environment.etc.composed.text == "true"
      # The pins make the nixpkgs of system-manager follow the nixpkgs
      # of this suite, so a set system-manager built itself would have
      # the same path and packages. Only the set the composition
      # declares has the probe.
      && (runsOn.pinnedWorldProbe or null) == "the set the composition declares"
      && system.config.services.userborn.package.drvPath == userborn.drvPath
      && !(builtins.tryEval withOverlay.drvPath).success
      && published.systemConfigs.default.drvPath == system.drvPath;

    # The ecosystem-args twins take the evaluator's arguments in
    # `ecosystemArgs`, applied last.
    ecosystemArgsTwinsReachTheEvaluator =
      let
        minimal = (
          hiveLib.caisson.integrations.topValue (
            hiveLib.caisson-core.finalizeTop (
              hiveLib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
                ecosystemSrc = inputs.nixpkgs;
                configModule =
                  { lib, ... }:
                  {
                    options.probe = lib.mkOption { type = lib.types.raw; };
                    config.probe = "minimal";
                  };
                ecosystemArgs.prefix = [ "probe-prefix" ];
              }
            )
          )
        );
        terraform = hiveLib.caisson.integrations.topValue (
          hiveLib.caisson-core.finalizeTop (
            hiveLib.caisson.terranix.mkConfigurationWithEcosystemArgs {
              ecosystemSrc = inputs.terranix;
              configModule = {
                config.terraform.required_version = ">= 1.0";
              };
              ecosystemArgs.strip_nulls = false;
            }
          )
        );
        home = hiveLib.caisson.integrations.topValue (
          hiveLib.caisson-core.finalizeTop (
            hiveLib.caisson.home-manager.mkConfigurationWithEcosystemArgs {
              ecosystemSrc = inputs.home-manager;
              configModule = {
                home.username = "probe";
                home.homeDirectory = "/home/probe";
                home.stateVersion = "24.05";
              };
              ecosystemArgs.check = false;
            }
          )
        );
      in
      minimal.config.probe == "minimal"
      && builtins.isString terraform.drvPath
      && builtins.isString home.activationPackage.drvPath;

    registeredModulesReachAdapters =
      let
        registeringLib = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
            projects.caisson = inputs.caisson;
            modules = lib: {
              nixos.pinned-world-probe = lib.caisson-core.mkModule "nixos" (
                { ... }:
                { lib, ... }:
                {
                  options.compatProbe = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                  };
                }
              );
            };
          }
        );
        system = registeringLib.caisson.nixos-minimal.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule =
            { lib, ... }:
            {
              options.nixpkgs.pkgs = lib.mkOption { type = lib.types.raw; };
            };
          # Selected by name: the default default is the entries named
          # `default`, and this entry is not.
          moduleImports = modules: [ modules.pinned-world-probe ];
        };
      in
      system.config.compatProbe;

    manifestTravelsWithMkLibCompositions =
      let
        composedWithMkLib = core.mkLib {
          sources = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          projects.caisson = inputs.caisson;
        };
        manifest = composedWithMkLib.caisson-core.libManifest;
      in
      includesAll [
        "configs"
        "defaultEcosystemSrc"
        "libOverlays"
        "modules"
        "projects"
        "root"
        "sources"
        "systems"
        "type"
      ] (builtins.attrNames manifest)
      && !(manifest ? name)
      && manifest.systems == null
      && composedWithMkLib.caisson-core.pkgsManifest == null
      && composedWithMkLib.caisson-core.evalManifest == null
      && includesAll (coreNames ++ [ "caisson/flake-parts" ]) (builtins.attrNames manifest.libOverlays)
      # The library of nixpkgs came in through the entry flake-parts
      # imports, from the source this composition declares.
      && composedWithMkLib ? evalModules
      && composedWithMkLib.caisson.flake-parts ? mkConfiguration;

    # A flake that takes caisson as a project composes each overlay of
    # caisson once. An integration imports the builder, the `framework`
    # entry and the nixpkgs library under the keys they have in
    # caisson. When caisson is consumed, those keys become
    # `caisson/<name>`, so each import resolves to the entry the
    # consumer registers under `caisson/<name>` and nothing is composed
    # under the bare key.
    integrationsComposeOnceInAConsumer =
      let
        keys = builtins.map (entry: entry.key) hiveLib.caisson-core.libManifest.entries;
        once = name: builtins.elem "caisson/${name}" keys && !(builtins.elem name keys);
      in
      once "integrations" && once "framework" && once "nixpkgs-lib" && once "nixos";

    # A tree declares its platforms on mkLib; the flake-parts
    # integration reads them from the manifest, so a flake module that
    # names no `systems` still enumerates them.
    systemsDeclaredOnMkLibReachFlakeParts =
      let
        composedWithSystems = core.mkLib {
          sources = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          defaultEcosystemSrc.flake-parts = inputs.flake-parts;
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          projects.caisson = inputs.caisson;
        };
        outputs = composedWithSystems.caisson.flake-parts.mkTopConfiguration {
          configModule = {
            perSystem =
              { system, ... }:
              {
                legacyPackages.probeSystem = system;
              };
          };
        };
      in
      builtins.attrNames outputs.legacyPackages == [
        "aarch64-linux"
        "x86_64-linux"
      ]
      && outputs.legacyPackages.x86_64-linux.probeSystem == "x86_64-linux";

    projectConsumptionComposesCaissonWhole =
      let
        composedFromProject = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
            projects = {
              caisson = inputs.caisson;
            };
          }
        );
        system = composedFromProject.caisson.nixos-minimal.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule =
            { pkgs, lib, ... }:
            {
              options.probe = lib.mkOption { type = lib.types.raw; };
              config.probe = pkgs ? hello;
            };
        };
      in
      composedFromProject.caisson.flake-parts ? mkConfiguration
      && composedFromProject.caisson-core.libManifest.modules.flake ? "caisson/default"
      && system.config.probe;

    declaredEcosystemServesAdapters =
      let
        composedWithDeclaration = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            defaultEcosystemSrc.nixpkgs = inputs.nixpkgs;
            projects.caisson = inputs.caisson;
          }
        );
        system = composedWithDeclaration.caisson.nixos-minimal.mkTopConfiguration {
          configModule =
            { lib, pkgs, ... }:
            {
              options.probePkgs = lib.mkOption { type = lib.types.raw; };
              config.probePkgs = pkgs;
            };
        };
      in
      system.config.probePkgs ? hello;

    nixpkgsHelpersWorkOnRealPkgs =
      let
        cn = composed.lib.caisson.nixpkgs;
        scoped = cn.mkScope pkgs (callPackage: {
          probe = callPackage ({ hello }: hello) { };
        });
        withPackages = pkgs.extend (
          (cn.mkPackagesOverlay (callPackage: {
            probe = callPackage ({ hello }: hello) { };
          }))
            "probeScope"
        );
        withPolyfill = pkgs.extend (
          (cn.mkPolyfillOverlay (final: prev: { polyfillProbe = prev.hello; })) "unused"
        );
      in
      scoped.probe.pname == "hello"
      && withPackages.probeScope.probe.pname == "hello"
      && withPolyfill.polyfillProbe.pname == "hello";

    # The structural integration: a top over the empty class returns
    # the selected registries with the manifest beside them, and the
    # same selectors under flake-parts export the same registries.
    structuralTopMatchesFlakeParts =
      let
        composedWithBoth = core.mkLib {
          sources = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          defaultEcosystemSrc.flake-parts = inputs.flake-parts;
          systems = [ "x86_64-linux" ];
          projects.caisson = inputs.caisson;
        };
        selectors = {
          caisson.libOverlays.exported = overlays: { inherit (overlays) "caisson/structural"; };
        };
        top = composedWithBoth.caisson.structural.mkTopConfiguration {
          configModule = selectors;
        };
        flake = composedWithBoth.caisson.flake-parts.mkTopConfiguration {
          configModule = selectors;
        };
      in
      builtins.attrNames top.libOverlays == [ "caisson/structural" ]
      && top.caisson.manifest ? modules
      # The `lib` output of the flake is the composed library, and the
      # manifest in it holds what the flake exports.
      && flake.lib ? caisson
      &&
        builtins.attrNames flake.lib.caisson-core.evalManifest.outputs.exports.libOverlays
        == [ "caisson/structural" ];

    # The modules that caisson exports work only inside an evaluation
    # that caisson makes. caisson publishes none of them in its
    # `modules` flake output. The output holds the empty `default`
    # entry of the `flake` class and nothing else. The modules are in
    # the manifest of caisson, where a flake that lists caisson in
    # `projects` reads them.
    caissonPublishesItsModulesInTheManifestOnly =
      let
        exported = inputs.caisson.lib.caisson-core.evalManifest.outputs.exports.modules;
      in
      builtins.mapAttrs (_class: builtins.attrNames) inputs.caisson.modules == {
        flake = [ "default" ];
      }
      # The lib overlays and package overlays that caisson exports are
      # entries in the shape caisson registers. They are in the
      # manifest and have no flake output.
      && !(inputs.caisson ? libOverlays)
      && !(inputs.caisson ? pkgOverlays)
      && inputs.caisson.lib.caisson-core.evalManifest.outputs.exports.libOverlays ? flake-parts
      && exported.nixos ? default
      && exported.nixos ? home-manager-activation
      && exported.homeManager ? nixos-parent
      && exported.flake ? nixpkgs;

  };

  failures = builtins.filter (n: results.${n} != true) (builtins.attrNames results);

in
{
  inherit results failures;
  ok = failures == [ ];
  summary =
    if failures == [ ] then
      "ok: ${toString (builtins.length (builtins.attrNames results))} tests passed"
    else
      throw "pinned-world suite failed: ${builtins.concatStringsSep ", " failures}";
}
