# SPDX-License-Identifier: MIT
#
# The pinned-world suite: caisson, the tree this file lives in,
# composed with concrete pinned versions of the upstream world
# (nixpkgs, home-manager, colmena, terranix, system-manager, read
# from tests/dependencies) and exercised end to end. Every upstream
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
  # overlays caisson exports, registered by mkLib and read back from
  # the manifest, each keyed by its registry name and importing the
  # published nixpkgs-lib entry. The suite composes them with
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
      libOverlays = _lib: inputs.caisson.libOverlays;
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
      registered.integrations
      registered.flake-parts
      registered.tooling
      registered.nixpkgs
      registered.nixos
      registered.nixos-minimal
      registered.home-manager
      registered.colmena
      registered.terranix
      registered.system-manager
      registered.structural
      # Last, so its value replaces the pin the overlays carry while
      # its position stays where the first import placed it.
      registered.nixpkgs-lib
    ];
  };

  # What lives under `caisson`: the integrations, the pkgs-dependent
  # tooling, and the names of the framework a tree writes, which the
  # `framework` overlay publishes from `caisson-core`.
  expectedCaissonNames = [
    "callConsumerFlake"
    "callFlake"
    "classes"
    "colmena"
    "configs"
    "contributeClasses"
    "contributeModules"
    "ecosystemSrc"
    "elide"
    "eval-weight"
    "evalManifest"
    "finalizeTop"
    "flake-parts"
    "home-manager"
    "importApply"
    "integrations"
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
    "nixos"
    "nixos-minimal"
    "nixpkgs"
    "pins"
    "pkgOverlays"
    "pkgOverlaysFor"
    "pkgsManifest"
    "realizeInputs"
    "structural"
    "system-manager"
    "terranix"
  ];

  expectedCoreNames = [
    "classes"
    "compose"
    "configs"
    "contributeClasses"
    "contributeModules"
    "coreEntries"
    "ecosystemSrc"
    "evalManifest"
    "importApply"
    "libManifest"
    "libOverlays"
    "mkExtendedLib"
    "mkLib"
    "mkLibOverlay"
    "mkLibOverlays"
    "mkModule"
    "mkModules"
    "modules"
    "pkgOverlays"
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
  # it: the system, and a package config whose set at that system is
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

  # The colmena probes compose with declared ecosystems: a node's
  # `ecosystemSrc` is colmena's, and nixpkgs resolves from the
  # declaration, as it does in a consumer flake.
  hiveLib = core.mkLib (
    declaresPkgs
    // {
      sources = { };
      projects = {
        caisson = inputs.caisson;
      };
      defaultEcosystemSrc = {
        inherit (inputs) nixpkgs colmena;
      };
    }
  );

  # A NixOS configuration with two homes declared inside it, evaluated
  # with the real home-manager over the real NixOS. The machine
  # declares the account of the first home and not the account of the
  # second, as with an account that systemd-homed manages.
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
              caisson.home-manager.configurations = {
                declared = home { };
                undeclared = home { home.homeDirectory = "/home/undeclared"; };
              };
            };
        };
      };
  };

  results = {

    composesTheCaissonLibrary =
      builtins.attrNames composed.lib.caisson == expectedCaissonNames
      && includesAll expectedCoreNames (builtins.attrNames composed.lib.caisson-core)
      &&
        composed.meta.order == coreNames
        ++ [
          "framework"
          "integrations"
          "nixpkgs-lib"
          "flake-parts"
          "tooling"
          "nixpkgs"
          "nixos"
          "nixos-minimal"
          "home-manager"
          "colmena"
          "terranix"
          "system-manager"
          "structural"
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
          imports = [ registered.nixpkgs-lib ];
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
          key = "nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: { stubMarker = true; };
        };
        r = compose {
          entries = builtins.map (name: registered.${name}) coreNames ++ [
            registered.flake-parts
            stub
          ];
        };
      in
      r.lib.stubMarker or false
      && !(r.lib ? evalModules)
      &&
        r.meta.order == coreNames
        ++ [
          "nixpkgs-lib"
          "framework"
          "integrations"
          "flake-parts"
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
      "colmena"
      "terranix"
      "system-manager"
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

    sourceMetaProvenanceIsCompositional =
      let
        meta = composed.lib.caisson.home-manager.mkSourceMeta {
          profileName = "pinned-world";
          homeManagerOutPath = "/probe-hm";
          nixpkgsOutPath = "/probe-np";
        };
      in
      meta.schemaVersion == 3 && meta.homeManagerOutPath == "/probe-hm" && meta ? fingerprint;

    ecosystemSrcValidationThrows =
      let
        throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      throws (
        composed.lib.caisson.colmena.mkConfiguration {
          ecosystemSrc = { };
          configModule = { };
        }
      )
      && throws (
        composed.lib.caisson.terranix.mkConfiguration {
          ecosystemSrc = { };
          configModule = { };
        }
      )
      && throws (
        composed.lib.caisson.system-manager.mkConfiguration {
          ecosystemSrc = { };
          configModule = { };
        }
      );

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
        meta = home.config.caisson-home-manager.sourceMeta;
      in
      builtins.isString home.activationPackage.drvPath
      && home.config.home.username == "probe"
      # The home runs on the package set the composition declares.
      && home.pkgs.pinnedWorldProbe == "the set the composition declares"
      && meta.schemaVersion == 3
      && meta.homeManagerOutPath == builtins.toString inputs.home-manager
      && meta.nixpkgsOutPath == builtins.toString pkgs.path;

    nixosAdapterUpstreamModeEvaluatesEndToEnd =
      let
        system = hiveLib.caisson.nixos.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule =
            { ... }:
            {
              imports = [
                minimalNixosBase
                (hiveLib.caisson.home-manager.mkNixosAdapter {
                  ecosystemSrc = inputs.home-manager;
                  hostName = "pinned-world-probe";
                  users.probe.configModule =
                    { ... }:
                    {
                      home.stateVersion = "25.05";
                    };
                })
              ];
              users.users.probe = {
                isNormalUser = true;
                home = "/home/probe";
              };
            };
        };
        # fromJSON refuses context-carrying strings; the marker file
        # embeds store paths as ordinary references.
        marker = builtins.fromJSON (
          builtins.unsafeDiscardStringContext
            system.config.environment.etc."caisson-home-manager/source.json".text
        );
      in
      builtins.isString system.config.system.build.toplevel.drvPath
      && system.config.home-manager.users.probe.home.stateVersion == "25.05"
      && marker.hostName == "pinned-world-probe"
      && marker.schemaVersion == 3;

    nixosAdapterUserServiceModeEvaluatesEndToEnd =
      let
        system = hiveLib.caisson.nixos.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule =
            { ... }:
            {
              imports = [
                minimalNixosBase
                (hiveLib.caisson.home-manager.mkNixosAdapter {
                  ecosystemSrc = inputs.home-manager;
                  activationMode = "user-service";
                  hostName = "pinned-world-probe-homed";
                  users.probe.configModule =
                    { ... }:
                    {
                      home.username = "probe";
                      home.homeDirectory = "/home/probe";
                      home.stateVersion = "25.05";
                    };
                })
              ];
            };
        };
      in
      builtins.isString system.config.caisson-home-manager.hostedActivations.probe.drvPath
      && system.config.systemd.user.services.home-manager.unitConfig.ConditionUser == "probe"
      && builtins.isString system.config.system.build.toplevel.drvPath;

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
        # The comparison is made on plain strings: a string that
        # refers to a store path cannot be searched for.
        plain = builtins.unsafeDiscardStringContext;
        runs =
          unit: home:
          pkgs.lib.hasInfix (plain "${home.activationPackage}/activate") (
            plain unit.serviceConfig.ExecStart.text
          );
      in
      systemUnit.serviceConfig.User == "declared"
      && systemUnit.unitConfig.RequiresMountsFor == "/home/declared"
      && runs systemUnit declared
      && userUnit.unitConfig.ConditionUser == "undeclared"
      && runs userUnit undeclared
      && !(machine.systemd.services ? home-manager-undeclared)
      && !(machine.systemd.user.services ? home-manager-declared)
      && builtins.isString machine.system.build.toplevel.drvPath;

    colmenaHiveEvaluatesEndToEnd =
      let
        hive = hiveLib.caisson.colmena.mkConfiguration {
          pkgSets.pkgs = pkgs;
          configModule =
            { mkNixosConfiguration, ... }:
            {
              meta.allowApplyAll = false;
              nodes.probe-node = mkNixosConfiguration {
                configModule = {
                  imports = [ minimalNixosBase ];
                  networking.hostName = "probe";
                  deployment.targetHost = "probe";
                };
              };
            };
        };
        node = hive.nodes.probe-node;
      in
      hive.__schema == (inputs.colmena.lib.makeHive { }).__schema
      && hive.toplevel.probe-node.drvPath == node.config.system.build.toplevel.drvPath
      && hive.deploymentConfig.probe-node.targetHost == "probe"
      && hive.metaConfig.allowApplyAll == false
      && builtins.attrNames (hive.evalSelectedDrvPaths [ "probe-node" ]) == [ "probe-node" ];

    # A node is the NixOS configuration nixos.mkConfiguration builds from
    # the same module, with colmena's deployment options declared: the
    # extra modules leave the system untouched. The node's ecosystem
    # source is nixpkgs, explicit here.
    colmenaNodesAreNixosConfigurations =
      let
        hostModule = {
          imports = [ minimalNixosBase ];
          networking.hostName = "probe";
        };
        hive = hiveLib.caisson.colmena.mkConfiguration {
          configModule =
            { mkNixosConfiguration, ... }:
            {
              nodes.probe = mkNixosConfiguration {
                ecosystemSrc = inputs.nixpkgs;
                configModule = hostModule;
              };
            };
        };
        node = hive.nodes.probe;
        system = hiveLib.caisson.nixos.mkTopConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          configModule = hostModule;
        };
      in
      node.config.system.build.toplevel.drvPath == system.config.system.build.toplevel.drvPath
      && node.options ? deployment
      && node.pkgs.hello.drvPath == pkgs.hello.drvPath;

    # A hive refuses a node that is not a colmena node. A node is
    # checked when it is read, so the probe forces a node.
    colmenaRefusesPlainNixosNodes =
      !(builtins.tryEval
        (hiveLib.caisson.colmena.mkConfiguration {
          configModule.nodes.plain = hiveLib.caisson.nixos.mkConfiguration {
            configModule = minimalNixosBase;
          };
        }).nodes.plain
      ).success;

    # Node names colmena's flat hive reserved (meta, defaults, network)
    # are ordinary names here. A node is an evaluated NixOS
    # configuration, so its module takes its host name from its
    # definitions rather than from a `name` argument.
    colmenaNodesAreNamedFreely =
      let
        hive = hiveLib.caisson.colmena.mkConfiguration {
          configModule =
            { mkNixosConfiguration, ... }:
            {
              nodes =
                builtins.mapAttrs
                  (
                    hostName: peer:
                    mkNixosConfiguration {
                      configModule =
                        { ... }:
                        {
                          imports = [ minimalNixosBase ];
                          networking.hostName = hostName;
                          deployment.targetHost = peer;
                          deployment.tags = [ peer ];
                        };
                    }
                  )
                  {
                    meta = "defaults";
                    defaults = "network";
                    network = "meta";
                  };
            };
        };
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
          !(builtins.tryEval
            (hiveLib.caisson.colmena.mkConfiguration {
              configModule =
                { mkNixosConfiguration, ... }:
                {
                  nodes.${nodeName} = mkNixosConfiguration {
                    configModule = minimalNixosBase;
                  };
                };
            }).nodes.${nodeName}
          ).success;
      in
      refused "a,b" && refused "@tagged" && refused "";

    terranixConfigurationEvaluatesEndToEnd =
      let
        terraform = composed.lib.caisson.terranix.mkConfiguration {
          ecosystemSrc = inputs.terranix;
          pkgSets.pkgs = pkgs;
          configModule = {
            config.terraform.required_version = ">= 1.0";
          };
        };
      in
      builtins.isString terraform.drvPath;

    systemManagerConfigEvaluatesEndToEnd =
      let
        config = composed.lib.caisson.system-manager.mkConfiguration {
          ecosystemSrc = inputs.system-manager;
          pkgSets.pkgs = pkgs;
          configModule = {
            config.system-manager.allowAnyDistro = true;
          };
        };
      in
      builtins.isString config.drvPath || builtins.isString (config.build.toplevel.drvPath or null);

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
        terraform = composed.lib.caisson.terranix.mkConfigurationWithEcosystemArgs {
          ecosystemSrc = inputs.terranix;
          configModule = {
            config.terraform.required_version = ">= 1.0";
          };
          ecosystemArgs = {
            inherit pkgs;
            strip_nulls = false;
          };
        };
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

    overlayBorneModulesReachAdapters =
      let
        contributingLib = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
            libOverlays = _lib: {
              nixos = inputs.caisson.libOverlays.nixos;
              nixos-minimal = inputs.caisson.libOverlays.nixos-minimal;
              contrib = core.mkLibOverlay (
                {
                  mkModule,
                  contributeModules,
                  ...
                }:
                {
                  imports = [ ];
                  overlay =
                    _final: prev:
                    contributeModules prev {
                      nixos.pinned-world-probe = mkModule "nixos" (
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
            };
          }
        );
        system = contributingLib.caisson.nixos-minimal.mkTopConfiguration {
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
          libOverlays = _lib: {
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
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
      && includesAll (coreNames ++ [ "flake-parts" ]) (builtins.attrNames manifest.libOverlays)
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
          libOverlays = _lib: {
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
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
      && composedFromProject.caisson-core.modules.flake ? "caisson/default"
      && system.config.probe;

    declaredEcosystemServesAdapters =
      let
        composedWithDeclaration = core.mkLib (
          declaresPkgs
          // {
            sources = { };
            defaultEcosystemSrc.nixpkgs = inputs.nixpkgs;
            libOverlays = _lib: {
              nixos = inputs.caisson.libOverlays.nixos;
              nixos-minimal = inputs.caisson.libOverlays.nixos-minimal;
            };
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
          libOverlays = _lib: {
            structural = inputs.caisson.libOverlays.structural;
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
        };
        selectors = {
          caisson.libOverlays.exported = overlays: { inherit (overlays) structural; };
        };
        top = composedWithBoth.caisson.structural.mkTopConfiguration {
          configModule = selectors;
        };
        flake = composedWithBoth.caisson.flake-parts.mkTopConfiguration {
          configModule = selectors;
        };
      in
      builtins.attrNames top.libOverlays == [ "structural" ]
      && builtins.attrNames flake.libOverlays == [ "structural" ]
      && top.caisson.manifest ? modules
      && top.lib == { };

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
