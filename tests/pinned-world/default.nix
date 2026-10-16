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
      registered."caisson/caisson-colmena"
      registered."caisson/terranix"
      registered."caisson/system-manager"
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
    "callConsumerFlake"
    "callFlake"
    "configs"
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
        inherit (inputs) nixpkgs colmena flake-parts;
      };
    }
  );

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
        "home-manager-source-marker"
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
          "caisson/caisson-colmena"
          "caisson/terranix"
          "caisson/system-manager"
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
      "caisson-colmena"
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

    # The same machine writes the file
    # `/etc/caisson-home-manager/source.json`. The file holds a store
    # path. The store path is the system of the machine with the homes
    # left out.
    #
    # The system that the machine builds has the units of the homes in
    # it. So the store path in the file must differ from the system
    # that the machine builds.
    #
    # Each home computes the same store path. The activation of each
    # home has a step that compares that store path with the file. The
    # script of the step must therefore contain the store path.
    aMachineRecordsWhatItsHomesCompareAgainst =
      let
        machine = machineWithHomes.nixosConfigurations.probe.config;
        homes = [
          machineWithHomes.homeConfigurations."declared@probe"
          machineWithHomes.homeConfigurations."undeclared@probe"
        ];
        # fromJSON refuses a string that refers to a store path.
        record = builtins.fromJSON (
          builtins.unsafeDiscardStringContext machine.environment.etc."caisson-home-manager/source.json".text
        );
        base = record.baseSystemOutPath;
        comparesAgainstIt =
          home:
          pkgs.lib.hasInfix base (
            builtins.unsafeDiscardStringContext home.config.home.activation.caissonMachineDrift.data
          );
      in
      builtins.attrNames record == [ "baseSystemOutPath" ]
      && pkgs.lib.hasPrefix builtins.storeDir base
      && base != builtins.unsafeDiscardStringContext machine.system.build.toplevel.outPath
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
    # configuration is always declared beneath another configuration,
    # so the caisson-colmena integration declares no `top`.
    onlyAnIntegrationWithATopHasMkTopConfiguration =
      hiveLib.caisson.nixos ? mkTopConfiguration
      && hiveLib.caisson.home-manager ? mkTopConfiguration
      && hiveLib.caisson.structural ? mkTopConfiguration
      && hiveLib.caisson.flake-parts ? mkTopConfiguration
      && !(hiveLib.caisson.caisson-colmena ? mkTopConfiguration);

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
