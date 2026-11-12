# SPDX-License-Identifier: MIT
#
# The pinned-world suite: caisson, the repository this file lives in,
# composed with concrete pinned versions of the upstream world
# (nixpkgs, home-manager, colmena, disko, nix-darwin, terranix,
# system-manager, microvm.nix, read from tests/dependencies) and
# exercised end to end. Every upstream
# expectation caisson relies on is held by a probe here, so a pin
# that moves and breaks an expectation fails at evaluation, in this
# suite, rather than in a consumer.
#
# The checks configuration (configs/flake/checks) runs it as the
# `pinned-world` check, so `nix flake check` evaluates the suite at the
# committed pins and a change to caisson is judged against the last
# known good world. The drift workflow advances the pins in the working
# tree, committing nothing, and runs the same check against today's
# upstreams.
#
# `inputs` are the inputs of the checks configuration, with `caisson`
# set to the flake of caisson evaluated from the source of this
# repository. Where tests/dependencies names a dependency that the
# flake.lock of caisson pins as well (caisson-core, flake-parts,
# nixpkgs-lib), `inputs` hold the pin of flake.lock. caisson-core is read
# through the composed library of caisson,
# `inputs.caisson.lib.caisson-core`, the caisson-core that caisson
# pins, and the suite composes no other.
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
  # `nixpkgs-lib` import of each exported overlay is the entry of the
  # flake that built it, caisson's pin; mkLib replaces every published
  # key with the entry of the flake that calls it, and a direct
  # composition does the same by listing the world's entry, since the
  # last occurrence of a key supplies its value.
  registered =
    (core.mkLib {
      dependencies = { inherit (inputs) nixpkgs-lib; };
      projects.caisson = inputs.caisson;
    }).caisson-core.libManifest.libOverlays;

  # The registry names of caisson-core's entries, read from the
  # registry: which entries caisson-core is made of is not something
  # caisson relies on, so the suite does not list them. caisson-core
  # runs this suite against its branches, and a branch that adds
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
      registered."caisson/nixos-test"
      registered."caisson/home-manager"
      registered."caisson/hjem"
      registered."caisson/caisson-colmena"
      registered."caisson/colmena"
      registered."caisson/caisson-disko"
      registered."caisson/disko"
      registered."caisson/caisson-facter"
      registered."caisson/facter"
      registered."caisson/caisson-microvm"
      registered."caisson/microvm"
      registered."caisson/caisson-nixops4-composite"
      registered."caisson/caisson-nixops4-resource"
      registered."caisson/nixops4"
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
      # Last, so its value replaces the pin the overlays import while
      # its position stays where the first import placed it.
      registered."caisson/nixpkgs-lib"
    ];
  };

  # What lives under `caisson`: the integrations, the pkgs-dependent
  # tooling, and the names of the framework a flake that uses caisson
  # writes, which the
  # `framework` overlay publishes from `caisson-core`.
  expectedCaissonNames = [
    "caisson-colmena"
    "caisson-disko"
    "caisson-facter"
    "caisson-microvm"
    "caisson-nixops4-composite"
    "caisson-nixops4-resource"
    "callConsumerFlake"
    "callFlake"
    "colmena"
    "configs"
    "darwin"
    "dependencies"
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
    "microvm"
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
    "nixops4"
    "nixos"
    "nixos-minimal"
    "nixos-test"
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
  # source, and the package set, the library and the NixOS module
  # collection resolve from the declaration, as they do in a consumer
  # flake. The library and the NixOS module collection are the same
  # nixpkgs pin as the package set.
  hiveLib = core.mkLib hiveLibArgs;
  hiveLibArgs = declaresPkgs // {
    dependencies = {
      inherit (inputs)
        nixpkgs
        colmena
        flake-parts
        disko
        home-manager
        nvf
        treefmt-nix
        nixvim
        nix-topology
        kubenix
        nixidy
        system-manager
        hjem
        terranix
        microvm
        nixops4
        nixops4-nixos
        ;
    };
    projects = {
      caisson = inputs.caisson;
    };
    defaultEcosystemSrc = dependencies: {
      nixpkgs-lib = dependencies.nixpkgs;
      nixos = dependencies.nixpkgs;
    };
  };

  # The registered world: the composition of `hiveLib` under the name
  # `pinned-world`, with a configuration registered for each class in
  # tests/pinned-world/configs. Its caisson top is the structural configuration
  # registered under that name, which declares a configuration of each
  # integration and gives none of them a module, so each takes the
  # module registered under its name.
  registeredLib = core.mkLib (
    hiveLibArgs
    // {
      name = "pinned-world";
      configs = lib: lib.caisson-core.mkModules ./configs;
    }
  );
  registeredWorld = registeredLib.caisson.structural.mkTopConfiguration { };

  # Every manifest of a caisson top, from the caisson top down through `children`. A
  # configuration evaluated per system has a manifest for each system,
  # with the configurations evaluated for that system inside it.
  manifestsOf =
    manifest:
    [ manifest ]
    ++ builtins.concatMap (
      byName:
      builtins.concatMap (
        value:
        if (value._type or null) == "caisson-manifest" then
          manifestsOf value
        else
          builtins.concatMap manifestsOf (builtins.attrValues value)
      ) (builtins.attrValues byName)
    ) (builtins.attrValues (manifest.children or { }));

  # Disk layouts as disko writes them, from disko's examples: a disk
  # with an ESP and LUKS around LVM, and one with mdadm, ZFS, LUKS and
  # LVM over three disks.
  luksLvmLayout = import "${inputs.disko}/example/luks-lvm.nix";
  complexLayout = import "${inputs.disko}/example/complex.nix";

  # What a NixOS configuration installed onto a layout needs beside the
  # layout, which gives it its file systems.
  diskoNixosBase = {
    boot.loader.grub.enable = false;
    system.stateVersion = "25.05";
  };

  # The NixOS configuration that NixOS evaluates from the NixOS module
  # of disko, the layout and `diskoNixosBase`, with no caisson
  # involved. Its host name is `nas-1`, the host name caisson gives the
  # NixOS configuration declared as `nas-1`.
  upstreamDiskoNixosConfiguration =
    layout:
    import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
      system = "x86_64-linux";
      modules = [
        "${inputs.disko}/module.nix"
        layout
        diskoNixosBase
        { networking.hostName = "nas-1"; }
      ];
    };

  # A caisson top holding a disko configuration of `integration` named
  # `nas-1`, over `layout`. With `nixosModule`, the layout declares a
  # NixOS configuration named `nas-1` from that module, installed onto
  # the layout. `args` are further arguments passed to `mkConfiguration`
  # for the layout.
  layoutTop =
    {
      integration,
      layout,
      nixosModule ? null,
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
                  if nixosModule == null then
                    { }
                  else
                    {
                      caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                        configModule = nixosModule;
                      };
                    }
                );
            }
          );
        };
    };

  # The manifest of the disko configuration `nas-1` of a `layoutTop`.
  layoutManifest = integration: top: top.caisson.manifest.children.${integration}.nas-1;

  # A caisson top holding a colmena configuration named `colmenaHive`, with a NixOS
  # configuration declared inside it for each NixOS module given, by
  # name. `nixosArgs` are further arguments of the constructor of each
  # NixOS configuration. The colmena configuration disallows a bare
  # `colmena apply`.
  colmenaTopWith =
    nixosArgs: nixosModules:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
            pkgSets.pkgs = pkgs;
            configModule =
              { lib, ... }:
              {
                meta.allowApplyAll = false;
                caisson.nixos.configurations = builtins.mapAttrs (
                  _: configModule: lib.caisson.nixos.mkConfiguration ({ inherit configModule; } // nixosArgs)
                ) nixosModules;
              };
          };
        };
    };
  colmenaTop = colmenaTopWith { };

  # A caisson top holding the root composite of a NixOps4 deployment, declared
  # under the name `nixops4`, which declares a resource for each NixOS
  # module given, by name, holding a NixOS configuration of that name. `root`
  # is a further module of the root composite, `resources` a further
  # module of each resource, by name, and `wiring` a function of the
  # `members` argument of the root composite returning more such
  # modules, by name, as a composite wires one member to another.
  # `defaultPkgs` is the selection of the root composite and
  # `nixosArgs` further arguments of the constructor of each NixOS
  # configuration.
  nixops4TopWith =
    {
      root ? { },
      resources ? { },
      wiring ? _: { },
      defaultPkgs ? null,
      nixosArgs ? { },
    }:
    nixosModules:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.caisson-nixops4-composite.configurations.nixops4 =
            lib.caisson.caisson-nixops4-composite.mkConfiguration
              {
                inherit defaultPkgs;
                configModule =
                  { lib, members, ... }:
                  {
                    imports = [ root ];
                    caisson.caisson-nixops4-resource.configurations = builtins.mapAttrs (
                      name: nixosModule:
                      lib.caisson.caisson-nixops4-resource.mkConfiguration {
                        configModule =
                          { lib, ... }:
                          {
                            imports = [
                              (resources.${name} or { })
                              ((wiring members).${name} or { })
                            ];
                            caisson.nixos.configurations.${name} = lib.caisson.nixos.mkConfiguration (
                              { configModule = nixosModule; } // nixosArgs
                            );
                          };
                      }
                    ) nixosModules;
                  };
              };
        };
    };

  # The entry the caisson top holds for the root composite named `nixops4`, of
  # the native or the upstream-compatible integration.
  nixops4Entry =
    top:
    let
      children = top.caisson.manifest.children;
    in
    (children.caisson-nixops4-composite or children.nixops4).nixops4;

  # The export of a root as NixOps4's command reads it: the root
  # function called with the deploying system and the outputs of each
  # resource, here `stub` for every output the resource declares, at
  # the fixpoint, as the command closes it.
  nixops4Export =
    root:
    let
      fixpoint = root.rootFunction {
        resourceProviderSystem = "x86_64-linux";
        outputValues = nixops4StubOutputs fixpoint.members;
      };
    in
    fixpoint;

  # The output values NixOps4 passes for the members of an export, with
  # `stub` for every output a resource declares.
  nixops4StubOutputs = builtins.mapAttrs (
    _: member:
    if member ? resource then
      builtins.mapAttrs (_: _: "stub") member.resource.outputsSkeleton
    else
      nixops4StubOutputs member.members
  );

  # The root composite of a caisson top's `nixops4`, finalized as NixOps4
  # finalizes it, with `stub` outputs: its manifest.
  nixops4RootManifest =
    top:
    (nixops4Entry top).finalize {
      args = {
        resourceProviderSystem = "x86_64-linux";
        outputValues = nixops4StubOutputs (nixops4Export top.nixops4).members;
      };
      argsSource = _: "the probe";
    };

  # A caisson top holding a nixops4 configuration named `nixops4` made from the
  # root modules given, as NixOps4's `mkRoot` takes them, with the
  # allow-list `cacheableOutputs`.
  nixops4UpstreamTopWith =
    {
      cacheableOutputs ? { },
    }:
    modules:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.nixops4.configurations.nixops4 = lib.caisson.nixops4.mkConfiguration {
            inherit modules cacheableOutputs;
          };
        };
    };

  # Root modules as a NixOps4 user writes them: a resource whose output
  # another member reads, a member that deploys NixOS through
  # nixops4-nixos, and a
  # nested composite holding a resource.
  nixops4UpstreamRoot =
    { providers, members, ... }:
    {
      _class = "nixops4Component";
      providers.local = inputs.nixops4.modules.nixops4Provider.local;
      members.address = {
        type = providers.local.exec;
        inputs.executable = "/bin/true";
      };
      members.probe = {
        imports = [ inputs.nixops4-nixos.modules.nixops4Component.nixos ];
        type = providers.local.exec;
        nixpkgs = inputs.nixpkgs;
        nixos.module = minimalNixosBase;
        ssh.host = members.address.outputs.stdout;
        ssh.hostPublicKey = nixops4HostKey;
      };
      members.group.members.inner = {
        type = providers.local.exec;
        inputs.executable = "/bin/false";
      };
    };

  # A host key for the machines NixOps4 deploys in the probes.
  nixops4HostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAiszi43aOWWV7voNgQ1Ifa7LGKwGJfOuiLM1n42h2Y8";

  # A further module of a native root composite: a resource `address`
  # of NixOps4's `local` provider, whose `stdout` another member reads.
  nixops4AddressRoot =
    { lib, ... }:
    {
      caisson.caisson-nixops4-resource.configurations.address =
        lib.caisson.caisson-nixops4-resource.mkConfiguration
          {
            configModule =
              { providers, ... }:
              {
                providers.local = inputs.nixops4.modules.nixops4Provider.local;
                type = providers.local.exec;
                inputs.executable = "/bin/true";
              };
          };
    };

  # The paths of the args an `argsNeeded` names, each a list of names.
  nixops4ArgPathsOf =
    let
      walk =
        path: value:
        if core.isArg value then
          [ path ]
        else
          builtins.concatMap (name: walk (path ++ [ name ]) value.${name}) (builtins.attrNames value);
    in
    walk [ ];

  # A native composite whose module is `module`, under `lib`.
  nixops4Composite =
    lib: module:
    lib.caisson.caisson-nixops4-composite.mkConfiguration {
      configModule = module;
    };

  # A native resource of the `exec` type of NixOps4's `local` provider,
  # with the further module `module`.
  nixops4Exec =
    lib: module:
    lib.caisson.caisson-nixops4-resource.mkConfiguration {
      configModule =
        { providers, ... }:
        {
          imports = [ module ];
          providers.local = inputs.nixops4.modules.nixops4Provider.local;
          type = providers.local.exec;
          inputs.executable = "/bin/true";
        };
    };

  # A native resource of the `state_file` type of NixOps4's `local`
  # provider, a resource that holds the state of others.
  nixops4StateFile =
    lib:
    lib.caisson.caisson-nixops4-resource.mkConfiguration {
      configModule =
        { providers, ... }:
        {
          providers.local = inputs.nixops4.modules.nixops4Provider.local;
          type = providers.local.state_file;
          inputs.name = "state.json";
        };
    };

  # A composite module that records its `members` argument as `seen`.
  nixops4SeesMembers =
    { lib, members, ... }:
    {
      options.seen = lib.mkOption { type = lib.types.raw; };
      config.seen = members;
    };

  # A caisson top whose root composite `nixops4` has the module `module`.
  nixops4RootTopWith =
    module:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.caisson-nixops4-composite.configurations.nixops4 = nixops4Composite lib module;
        };
    };

  # Whether forcing a value fails with an error a probe can catch.
  nixops4Fails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;

  # A deferred configuration of a tool that is not NixOps4, declared
  # beside a NixOps4 deployment: it takes the cacheable arg `who` and
  # greets it. Its entry is published as `greetings.<name>`, a function
  # of `who`, and its discovery program is named `greeter-discover`.
  greeterConfiguration =
    lib:
    lib.caisson-core.mkDeferredConfiguration {
      type = "greeter";
      record.exportsTo = {
        attrset = "greetings";
        value =
          entry: who:
          (entry.finalize {
            args = { inherit who; };
            argsSource = _: "the probe";
          }).outputs.greeting;
      };
      configuration =
        {
          name,
          parent,
          args,
        }:
        lib.caisson.integrations.mkModuleConfiguration {
          type = "greeter";
          evaluate =
            { lib, ... }:
            let
              evaluated = lib.evalModules {
                specialArgs = { inherit lib; };
                modules = lib.caisson.integrations.frameworkModules "structural" { } ++ [
                  (
                    { lib, ... }:
                    {
                      options.greeting = lib.mkOption { type = lib.types.str; };
                      config.greeting = "hello ${args.who}";
                    }
                  )
                ];
              };
            in
            {
              value = evaluated;
              outputs.greeting = evaluated.config.greeting;
              argsNeeded.who = lib.caisson-core.mkArg { cacheable = true; };
              discoverArgs = { system }: pkgs.writeShellScript "greeter-discover" "echo '{\"who\":\"world\"}'";
            };
        } { inherit name parent; };
    };

  # What a microvm.nix guest needs beside what microvm.nix's guest
  # module gives it, which boots it and gives it its file systems.
  microvmGuestBase = {
    system.stateVersion = "25.05";
  };

  # A guest in microvm.nix's own form, as microvm.nix's examples write
  # one: it runs on qemu and reads the store of its host over 9p.
  upstreamMicrovmGuest = {
    imports = [ microvmGuestBase ];
    microvm = {
      hypervisor = "qemu";
      mem = 640;
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "9p";
        }
      ];
    };
  };

  # A guest in caisson's form that sets the `microvm.*` options itself: it
  # runs on cloud-hypervisor with two virtual CPUs, 768 megabytes, the
  # vsock CID 3 and the store of its host over virtiofs.
  cloudHypervisorGuest = {
    imports = [ microvmGuestBase ];
    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 2;
      mem = 768;
      vsock.cid = 3;
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "virtiofs";
        }
      ];
    };
  };

  # A NixOS host named `host` that selects caisson's `microvm-host`
  # module, inside the structural caisson top of `registeredLib`. The host holds
  # the caisson-microvm configuration `pool` and the microvm
  # configuration `upstream`. `pool` starts its guests at boot and
  # leaves a running guest whose configuration changed as it is. Its
  # guest `a` sets the `microvm.*` options itself. Its guest `b` sets none
  # of them. Its guest `c` selects its modules itself, caisson's
  # `microvm-guest` NixOS module alone.
  microvmHostTop = registeredLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.host = lib.caisson.nixos.mkConfiguration {
          extraModuleImports = modules: [ modules."caisson/microvm-host" ];
          configModule =
            { lib, ... }:
            {
              imports = [ minimalNixosBase ];
              caisson.caisson-microvm.configurations.pool = lib.caisson.caisson-microvm.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    autostart = true;
                    restartIfChanged = false;
                    caisson.nixos.configurations.a = lib.caisson.nixos.mkConfiguration {
                      configModule = cloudHypervisorGuest;
                    };
                    caisson.nixos.configurations.b = lib.caisson.nixos.mkConfiguration {
                      configModule = microvmGuestBase;
                    };
                    caisson.nixos.configurations.c = lib.caisson.nixos.mkConfiguration {
                      moduleImports = modules: [ modules."caisson/microvm-guest" ];
                      configModule = microvmGuestBase;
                    };
                  };
              };
              caisson.microvm.configurations.upstream = lib.caisson.microvm.mkConfiguration {
                configModule = upstreamMicrovmGuest;
              };
            };
        };
      };
  };

  # A hive in the format colmena reads, with every feature the
  # upstream-compatible integration supports: `meta.nixpkgs`, shared and
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

  # A caisson top holding the upstream hive as a colmena configuration named
  # `colmenaHive`.
  upstreamHiveTop = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.colmena.configurations.colmenaHive = lib.caisson.colmena.mkConfiguration {
          hive = upstreamHive;
        };
      };
  };

  # A NixOS configuration with two home-manager configurations
  # declared inside it, evaluated with the real home-manager over the
  # real NixOS. The NixOS configuration declares the account of the
  # first home-manager configuration. It does not declare the account of the
  # second, and lists that user as declared elsewhere, as for an
  # account that systemd-homed manages.
  nixosConfigurationWithHomeManagerConfigurations = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule =
            { lib, ... }:
            let
              homeManagerConfiguration =
                module:
                lib.caisson.home-manager.mkConfiguration {
                  ecosystemSrc = dependencies: dependencies.home-manager;
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
                declared = homeManagerConfiguration { };
                undeclared = homeManagerConfiguration { home.homeDirectory = "/home/undeclared"; };
              };
            };
        };
      };
  };

  # The same NixOS configuration, with home-manager configurations that
  # set `caisson.useUserPackages`: a home-manager configuration for the
  # account the NixOS configuration declares, another for the user
  # declared elsewhere, and a third, for another declared account, that
  # leaves it unset.
  nixosConfigurationWithUserPackages = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule =
            { lib, ... }:
            let
              homeManagerConfiguration =
                module:
                lib.caisson.home-manager.mkConfiguration {
                  ecosystemSrc = dependencies: dependencies.home-manager;
                  configModule =
                    { pkgs, ... }:
                    {
                      imports = [ module ];
                      home.stateVersion = "25.05";
                      home.packages = [ pkgs.hello ];
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
              users.users.plain = {
                isNormalUser = true;
                home = "/home/plain";
                uid = 1002;
              };
              caisson.home-manager.activation.usersDeclaredElsewhere = [ "undeclared" ];
              caisson.home-manager.configurations = {
                declared = homeManagerConfiguration { caisson.useUserPackages = true; };
                undeclared = homeManagerConfiguration {
                  home.homeDirectory = "/home/undeclared";
                  caisson.useUserPackages = true;
                };
                plain = homeManagerConfiguration { };
              };
            };
        };
      };
  };

  # The library caisson evaluates a NixOS configuration on. It has
  # `lib.caisson`, and it holds the manifest of that evaluation result.
  #
  # The check `aNixosModuleImportsWhatDeclaresItsCaissonOptions` below
  # needs such a library without the evaluation result it came from. A
  # module of the NixOS configuration hands the library out through an
  # option.
  nixosEvaluationLib =
    (hiveLib.caisson.nixos.mkTopConfiguration {
      ecosystemSrc = dependencies: dependencies.nixpkgs;
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

  # The checks probes compose for two systems, x86_64-linux and
  # aarch64-linux, with a package config whose set for each of them is
  # `pkgs`. A check is a derivation that only writes its output, named
  # for the check.
  checksSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  checksLib = core.mkLib checksLibArgs;
  checksLibArgs = (
    hiveLibArgs
    // {
      systems = checksSystems;
      pkgSets = _lib: {
        default =
          { name, parent }:
          {
            _type = "caisson-manifest";
            type = "nixpkgs";
            inherit name parent;
            children.nixpkgs = pkgs.lib.genAttrs checksSystems (system: {
              _type = "caisson-manifest";
              type = "nixpkgs";
              name = system;
              value = pkgs;
            });
          };
      };
    }
  );
  checkMarker = name: pkgs.runCommand name { } "touch $out";
  checksNixosConfiguration =
    lib: module:
    lib.caisson.nixos.mkConfiguration {
      ecosystemSrc = dependencies: dependencies.nixpkgs;
      configModule = {
        imports = [
          minimalNixosBase
          module
        ];
      };
    };

  # A structural caisson top that declares the category `hardware` and the stage
  # `quick`. The NixOS configuration `nas-1`, evaluated for both
  # systems, declares the checks `smoke` and `boots`, and the check
  # `off`, which it turns off. The structural configuration `lab`
  # evaluates the configurations inside it for aarch64-linux, and the
  # NixOS configuration `arm` inside it declares the check `smoke`.
  checksTopWith =
    extra:
    checksLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          imports = [ extra ];
          caisson.checkCategories.hardware = {
            description = "the machine boots on its hardware";
            volatile = true;
          };
          caisson.checkStages.quick = {
            description = "the checks that evaluate";
            select = entry: entry.category == "eval";
          };
          caisson.structural.configurations.lab = lib.caisson.structural.mkConfiguration {
            configModule =
              { lib, ... }:
              {
                caisson.forChildren.systems = [ "aarch64-linux" ];
                caisson.nixos.configurations.arm = checksNixosConfiguration lib {
                  caisson.checks.smoke = {
                    derivation = checkMarker "arm-smoke";
                    category = "eval";
                    description = "the NixOS configuration evaluates";
                  };
                };
              };
          };
          caisson.nixos.configurations.nas-1 = checksNixosConfiguration lib {
            caisson.checks.smoke = {
              derivation = checkMarker "nas-1-smoke";
              category = "eval";
              description = "the NixOS configuration evaluates";
            };
            caisson.checks.boots = {
              derivation = pkgs.runCommand "nas-1-boots" { requiredSystemFeatures = [ "kvm" ]; } "touch $out";
              category = "hardware";
            };
            caisson.checks.off = {
              derivation = checkMarker "nas-1-off";
              category = "eval";
              enable = false;
            };
          };
        };
    };
  checksTop = checksTopWith { };

  # True when reading `value`, checks by system and then name or a
  # check record, fails: every name is read, and the store path of
  # every derivation, or every field of every record entry.
  checksFail =
    value:
    !(builtins.tryEval (
      builtins.deepSeq (builtins.mapAttrs (
        _: builtins.mapAttrs (_: entry: if entry ? drvPath then entry.drvPath else entry)
      ) value) true
    )).success;

  # A flake that declares checks under `perSystem`: `plain`, an entry of
  # `checks` that `caisson.checks` annotates, `bare`, an entry of
  # `checks` nothing annotates, `declared`, a check `caisson.checks`
  # declares, and `hidden`, a check it declares and turns off. The NixOS
  # configuration `nas-1` inside the flake declares the check `smoke`,
  # and the flake-parts configuration `checks` inside it defines the
  # check `suite` under `perSystem`.
  checksFlake = checksLib.caisson.flake-parts.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        perSystem =
          { ... }:
          {
            checks.plain = checkMarker "plain";
            checks.bare = checkMarker "bare";
            caisson.checks.plain = {
              category = "format";
              description = "the files are formatted";
            };
            caisson.checks.declared = {
              derivation = checkMarker "declared";
              category = "unit";
            };
            caisson.checks.hidden = {
              derivation = checkMarker "hidden";
              category = "eval";
              enable = false;
            };
          };
        caisson.nixos.configurations.nas-1 = checksNixosConfiguration lib {
          caisson.checks.smoke = {
            derivation = checkMarker "nas-1-smoke";
            category = "eval";
          };
        };
        caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
          moduleImports = _modules: [ ];
          configModule = {
            perSystem.checks.suite = checkMarker "suite";
          };
        };
      };
  };

  # A configuration of an integration written for the probe, `stub`,
  # evaluated per system as the module system over the core module of
  # the nixos class, which declares `caisson.checks` at the top level of
  # the options. The integration declares the default check `artifact`, of
  # the category `probe`, which it declares as well.
  # The library of the registries probes: `checksLib` with the NixOS
  # modules of tests/pinned-world/registries registered, `undeclared`,
  # which defines an option under `caisson` and imports nothing, and
  # `declared`, which defines the same option and imports the core
  # module of caisson for the nixos class.
  registriesLib = core.mkLib (
    checksLibArgs
    // {
      modules = lib: lib.caisson-core.mkModules ./registries/modules;
    }
  );

  # A structural caisson top on `registriesLib` whose NixOS
  # configuration `nas-1` selects the registered module `entry`, with
  # the modules `nixos.default` selects.
  registriesTopWith =
    entry:
    registriesLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
            ecosystemSrc = dependencies: dependencies.nixpkgs;
            extraModuleImports = modules: [ modules.${entry} ];
            configModule = minimalNixosBase;
          };
        };
    };

  # The default checks of the integrations: a structural caisson top
  # on `hiveLib` that declares a NixOS configuration, a home-manager
  # configuration, a system-manager configuration, a terranix
  # configuration and a flake-parts configuration whose `perSystem`
  # declares the package `hello`.
  defaultChecksTop = hiveLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule = minimalNixosBase;
        };
        caisson.home-manager.configurations.alice = lib.caisson.home-manager.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.home-manager;
          configModule = {
            home.username = "alice";
            home.homeDirectory = "/home/alice";
            home.stateVersion = "25.05";
          };
        };
        caisson.system-manager.configurations.box = lib.caisson.system-manager.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.system-manager;
          configModule.config.system-manager.allowAnyDistro = true;
        };
        caisson.terranix.configurations.infra = lib.caisson.terranix.mkConfiguration {
          ecosystemSrc = dependencies: dependencies.terranix;
          configModule.config.terraform.required_version = ">= 1.0";
        };
        caisson.flake-parts.configurations.tools = lib.caisson.flake-parts.mkConfiguration {
          moduleImports = _modules: [ ];
          configModule = {
            perSystem =
              { pkgs, ... }:
              {
                packages.hello = pkgs.runCommand "hello" { } "touch $out";
              };
          };
        };
      };
  };

  stubChecksTopWith =
    module:
    let
      lib = checksLib;
    in
    lib.caisson.finalizeTop (
      lib.caisson.integrations.mkModuleConfiguration {
        type = "stub";
        perSystem = true;
        checks =
          { outputs, ... }:
          {
            artifact = {
              derivation = outputs.artifact;
              category = "probe";
              description = "the artifact of the configuration builds";
            };
          };
        checkCategories.probe = {
          description = "a check of the probe integration";
          volatile = true;
        };
        evaluate =
          { lib, manifest }:
          {
            value = lib.evalModules {
              specialArgs = { inherit lib; };
              modules = lib.caisson.integrations.frameworkModules "nixos" { } ++ [ module ];
            };
            outputs.artifact = checkMarker "stub-artifact-${manifest.system}";
          };
      }
    );

  # A NixOS test as `pkgs.testers.runNixOSTest` takes it: the test
  # `probe`, with the node `machine` that logs root in on the console.
  nixosTestModule = {
    name = "probe";
    nodes.machine = {
      services.getty.autologinUser = "root";
    };
    testScript = ''
      machine.wait_for_unit("multi-user.target")
    '';
  };

  # A structural caisson top that declares the test of
  # `nixosTestModule` as the nixos-test configuration `probe`.
  nixosTestTop = checksLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos-test.configurations.probe = lib.caisson.nixos-test.mkConfiguration {
          configModule = nixosTestModule;
        };
      };
  };

  # A flake that declares the test of `nixosTestModule` as the
  # nixos-test configuration `probe`, at the top of the flake.
  nixosTestFlake = checksLib.caisson.flake-parts.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos-test.configurations.probe = lib.caisson.nixos-test.mkConfiguration {
          configModule = nixosTestModule;
        };
      };
  };

  # A structural caisson top with the NixOS configuration `nas-1`, whose
  # host name is `nas-one`, and the nixos-test configuration `smoke`
  # declared inside it. The test names itself after the host name of
  # the NixOS configuration it is declared inside, read from its
  # manifest.
  nixosTestInsideNixos = checksLib.caisson.structural.mkTopConfiguration {
    moduleImports = _modules: [ ];
    configModule =
      { lib, ... }:
      {
        caisson.nixos.configurations.nas-1 = checksNixosConfiguration lib (
          { lib, ... }:
          {
            networking.hostName = "nas-one";
            caisson.nixos-test.configurations.smoke = lib.caisson.nixos-test.mkConfiguration {
              configModule =
                { lib, ... }:
                {
                  name = lib.caisson-core.evalManifest.nearest.nixos.value.config.networking.hostName;
                  nodes.machine = { };
                  testScript = ''
                    machine.wait_for_unit("multi-user.target")
                  '';
                };
            };
          }
        );
      };
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

    # A user who is not on caisson imports a module from the `modules`
    # output of a caisson flake into a NixOS configuration that
    # `nixosSystem` of nixpkgs evaluates. That NixOS configuration is
    # evaluated on the library of nixpkgs.
    #
    # The flake `publisher` registers the module from
    # tests/pinned-world/modules and publishes it as
    # `modules.nixos.published`. The NixOS configuration builds, and the
    # file that the module writes shows two things. The module read the
    # library of `publisher` through `closure-lib`. The `lib` that
    # `nixosSystem` gave the module has no `caisson`.
    aPublishedModuleEvaluatesUnderPlainNixosSystem =
      let
        publisher =
          (core.mkLib (
            hiveLibArgs
            // {
              name = "publisher";
              modules = lib: lib.caisson-core.mkModules ./modules;
            }
          )).caisson.flake-parts.mkTopConfiguration
            { };
        evaluated = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            minimalNixosBase
            publisher.modules.nixos.published
          ];
        };
        written = builtins.fromJSON evaluated.config.environment.etc."pinned-world/published.json".text;
      in
      !(inputs.nixpkgs.lib ? caisson)
      && builtins.attrNames publisher.modules.nixos == [ "published" ]
      &&
        written == {
          definedIn = "publisher";
          evaluatorLibHasCaisson = false;
        }
      && builtins.isString evaluated.config.system.build.toplevel.drvPath;

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
          "caisson/nixos-test"
          "caisson/home-manager"
          "caisson/hjem"
          "caisson/caisson-colmena"
          "caisson/colmena"
          "caisson/caisson-disko"
          "caisson/disko"
          "caisson/caisson-facter"
          "caisson/facter"
          "caisson/caisson-microvm"
          "caisson/microvm"
          "caisson/caisson-nixops4-resource"
          "caisson/caisson-nixops4-composite"
          "caisson/nixops4"
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
    # world, not from the pin of the flake that built the exported
    # overlays. In the checks of caisson the declared world takes
    # nixpkgs-lib from the flake.lock of caisson, since that pin shadows
    # the nixpkgs-lib of tests/dependencies, so the two are the same
    # tree there. The drift workflow advances that pin in flake.lock,
    # so the probe runs against today's nixpkgs-lib.
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
        dependencies = { inherit (inputs) nixpkgs-lib; };
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
      "caisson-microvm"
      "microvm"
      "caisson-nixops4-composite"
      "caisson-nixops4-resource"
      "nixops4"
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
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          # The minimal evaluator imports no nixpkgs module, so the
          # package set is passed as the `pkgs` module argument.
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
              caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                ecosystemSrc = dependencies: { };
              };
            };
        }).colmenaHive
      &&
        throws
          (hiveLib.caisson.terranix.mkTopConfiguration {
            ecosystemSrc = dependencies: { };
            configModule = { };
          }).drvPath
      &&
        throws
          (hiveLib.caisson.system-manager.mkTopConfiguration {
            ecosystemSrc = dependencies: { };
            configModule = { };
          }).drvPath;

    homeConfigurationEvaluatesEndToEnd =
      let
        # A home-manager configuration takes its system and its
        # package set from the composition, and a caisson top is read as the
        # home-manager CLI reads it: the evaluated home-manager
        # configuration.
        homeManagerConfiguration = hiveLib.caisson.home-manager.mkTopConfiguration {
          ecosystemSrc = dependencies: dependencies.home-manager;
          configModule =
            { ... }:
            {
              home.username = "probe";
              home.homeDirectory = "/home/probe";
              home.stateVersion = "25.05";
            };
        };
      in
      builtins.isString homeManagerConfiguration.activationPackage.drvPath
      && homeManagerConfiguration.config.home.username == "probe"
      # The home-manager configuration runs on the package set the
      # composition declares.
      && homeManagerConfiguration.pkgs.pinnedWorldProbe == "the set the composition declares"
      # The home-manager command of the home-manager configuration
      # comes from the home-manager source the home-manager
      # configuration was evaluated with.
      &&
        homeManagerConfiguration.config.programs.home-manager.path == builtins.toString inputs.home-manager;

    # Two home-manager configurations declared inside a NixOS
    # configuration, evaluated with the real home-manager over the real
    # NixOS. The NixOS configuration declares the account of the first
    # home-manager configuration and not the account of the second, as
    # with an account that systemd-homed manages.
    #
    # Each home-manager configuration is given the Nix of the NixOS
    # configuration, and each builds an activation package, which forces
    # home-manager's whole module tree with the `config` of the NixOS
    # configuration handed in as `osConfig`. The first home-manager
    # configuration takes its home directory and its user ID from the
    # account. The second home-manager configuration sets its home
    # directory itself.
    homeManagerConfigurationsInsideANixosConfigurationAreGivenIt =
      let
        nixosConfig = nixosConfigurationWithHomeManagerConfigurations.nixosConfigurations.probe.config;
        declared = nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."declared@probe";
        undeclared = nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."undeclared@probe";
        hasTheProgram =
          homeManagerConfiguration:
          builtins.elem homeManagerConfiguration.config.programs.home-manager.package homeManagerConfiguration.config.home.packages;
      in
      builtins.isString declared.activationPackage.drvPath
      && builtins.isString undeclared.activationPackage.drvPath
      && declared.config.home.homeDirectory == "/home/declared"
      && declared.config.home.uid == 1001
      && undeclared.config.home.homeDirectory == "/home/undeclared"
      && undeclared.config.home.uid == null
      && declared.config.nix.package == nixosConfig.nix.package
      && undeclared.config.nix.package == nixosConfig.nix.package
      && declared.config.submoduleSupport.enable
      && undeclared.config.submoduleSupport.enable
      && hasTheProgram declared
      && hasTheProgram undeclared;

    # The manifest a caisson top publishes holds the export record, an entry
    # for each name the caisson top publishes, keyed as the outputs are. The
    # name path of an entry, followed from that manifest through
    # `children`, leads to the configuration published under the name.
    # The home-manager integration names a home-manager configuration
    # after the NixOS configuration it is inside, and the entry holds
    # the sentence the integration wrote for that, and the position in
    # the file of the integration where it gives its `exportsTo`.
    exportRecordLeadsToWhatIsPublished =
      let
        top = nixosConfigurationWithHomeManagerConfigurations.caisson.manifest;
        record = top.exportRecord;
        follow = builtins.foldl' (manifest: segment: manifest.children.${segment.type}.${segment.name}) top;
        declared = record.homeConfigurations."declared@probe";
        probe = record.nixosConfigurations.probe;
        inIntegration =
          integration: position:
          pkgs.lib.hasSuffix "/lib-overlays/${integration}/default.nix" position.file
          && builtins.isInt position.line;
      in
      builtins.attrNames record == [
        "homeConfigurations"
        "nixosConfigurations"
      ]
      &&
        builtins.attrNames record.homeConfigurations == [
          "declared@probe"
          "undeclared@probe"
        ]
      &&
        (follow declared.from.namePath).value.activationPackage.drvPath
        == nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."declared@probe".activationPackage.drvPath
      &&
        (follow probe.from.namePath).value.config.system.build.toplevel.drvPath
        == nixosConfigurationWithHomeManagerConfigurations.nixosConfigurations.probe.config.system.build.toplevel.drvPath
      &&
        declared.notes
        == [ "named declared@probe from its name and the name of the NixOS configuration it is under" ]
      && probe.notes == [ ]
      && builtins.length declared.code == 1
      && inIntegration "home-manager" (builtins.head declared.code)
      && builtins.length probe.code == 1
      && inIntegration "nixos" (builtins.head probe.code);

    # The history of a NixOS configuration records what eval-config
    # received, as `declaration` events of its manifest: NixOS' module
    # list as a single event, the framework module of caisson, the
    # modules selected from the registry by their registry keys, the
    # module of the configuration, and the module that hands it the
    # package set. The history of a home-manager configuration inside
    # it begins with the history of the manifest of the result of the
    # childless evaluation of the NixOS configuration.
    aNixosConfigurationRecordsWhatItsEvaluatorReceived =
      let
        probe =
          nixosConfigurationWithHomeManagerConfigurations.caisson.manifest.children.system.x86_64-linux.children.nixos.probe;
        path = [
          {
            type = "system";
            name = "x86_64-linux";
          }
          {
            type = "nixos";
            name = "probe";
          }
        ];
        ofProbe = builtins.filter (event: event.manifest == path) probe.history;
        declared = probe.children.system.x86_64-linux.children.home-manager.declared;
        prefix = builtins.length probe.childlessManifest.history;
        identity = event: {
          inherit (event)
            manifest
            operation
            index
            key
            ;
        };
      in
      builtins.map (event: event.key) ofProbe == [
        "nixos"
        "caisson.nixos"
        "modules.nixos.caisson/core"
        "modules.nixos.caisson/default"
        "inline/4"
        "caisson.nixos.pkgSet"
      ]
      && builtins.all (event: event.operation == "declaration" && event.type == "nixos") ofProbe
      && builtins.map (event: event.index) ofProbe == pkgs.lib.range 0 5
      &&
        (builtins.head ofProbe).origin == {
          project = "nixpkgs";
          file = "nixos/modules/module-list.nix";
        }
      &&
        (builtins.elemAt ofProbe 1).origin == {
          project = "caisson";
          file = "modules/nixos/core";
        }
      &&
        builtins.map identity (pkgs.lib.take prefix declared.history)
        == builtins.map identity probe.childlessManifest.history
      && builtins.length declared.history > prefix;

    # Every module caisson adds to a configuration is keyed, so the
    # history of the evaluation result names it. The suite walks every
    # manifest of the caisson tops of the pinned world below, from the top
    # down through `children`, which holds a configuration of every
    # integration. An `inline/<index>` event is a module a
    # configuration was given as a value, and the only such events are
    # the modules the suite passes as `configModule` itself, each listed
    # here by the configuration it was passed to.
    #
    # The registered world declares a configuration of each
    # integration and gives none of them a module. Each records the
    # module registered under its name as `configs.<class>.<name>`,
    # with the project of the composition and the file of the
    # registered configuration, and none records an `inline/<index>`
    # event.
    everyModuleCaissonAddsIsNamed =
      let
        darwin = import ../darwin-system { inherit inputs; };
        hjem = import ../hjem-system { inherit inputs; };
        declarationsOf =
          top:
          builtins.filter (event: event.operation == "declaration") (
            builtins.concatMap (manifest: manifest.history) (manifestsOf top.caisson.manifest)
          );
        placeOf =
          event:
          if event.manifest == [ ] then
            "top"
          else
            builtins.concatStringsSep " / " (
              builtins.map (segment: "${segment.type} ${segment.name}") event.manifest
            );
        # The `inline/<index>` events of a caisson top, each as the place of
        # the configuration that records it and its key, once.
        inlineOf =
          top:
          builtins.sort builtins.lessThan (
            pkgs.lib.unique (
              builtins.map (event: "${placeOf event}: ${event.key}") (
                builtins.filter (event: pkgs.lib.hasPrefix "inline/" event.key) (declarationsOf top)
              )
            )
          );
        expected = builtins.mapAttrs (_: builtins.sort builtins.lessThan) {
          registered = [ ];
          nixosConfigurationWithHomeManagerConfigurations = [
            "top: inline/2"
            "system x86_64-linux / nixos probe: inline/4"
            "system x86_64-linux / nixos probe / system x86_64-linux / home-manager declared: inline/4"
            "system x86_64-linux / nixos probe / system x86_64-linux / home-manager undeclared: inline/4"
          ];
          upstreamHive = [ "top: inline/2" ];
          colmena = [
            "top: inline/2"
            "caisson-colmena colmenaHive: inline/4"
            "caisson-colmena colmenaHive / system x86_64-linux / nixos probe-node: inline/5"
          ];
          caissonDisko = [
            "top: inline/2"
            "caisson-disko nas-1: inline/5"
            "caisson-disko nas-1 / system x86_64-linux / nixos nas-1: inline/5"
          ];
          disko = [
            "top: inline/2"
            "disko nas-1: inline/4"
          ];
          darwin = [
            "top: inline/2"
            "system aarch64-darwin / darwin probe: inline/3"
            "system aarch64-darwin / darwin family: inline/3"
            "system aarch64-darwin / darwin family / system aarch64-darwin / home-manager probe: inline/4"
            "system aarch64-darwin / darwin family / system aarch64-darwin / hjem probe: inline/6"
          ];
          hjem = [
            "top: inline/2"
            "system x86_64-linux / nixos probe-nixos: inline/4"
            "system x86_64-linux / nixos probe-nixos / system x86_64-linux / hjem probe: inline/7"
          ];
          microvm = [
            "top: inline/2"
            "system x86_64-linux / nixos host: inline/5"
            "system x86_64-linux / nixos host / caisson-microvm pool: inline/4"
            "system x86_64-linux / nixos host / caisson-microvm pool / system x86_64-linux / nixos a: inline/5"
            "system x86_64-linux / nixos host / caisson-microvm pool / system x86_64-linux / nixos b: inline/5"
            "system x86_64-linux / nixos host / caisson-microvm pool / system x86_64-linux / nixos c: inline/4"
            "system x86_64-linux / nixos host / system x86_64-linux / microvm upstream: inline/4"
          ];
        };
        recorded = {
          registered = inlineOf registeredWorld;
          nixosConfigurationWithHomeManagerConfigurations = inlineOf nixosConfigurationWithHomeManagerConfigurations;
          upstreamHive = inlineOf upstreamHiveTop;
          colmena = inlineOf (colmenaTop {
            probe-node = minimalNixosBase;
          });
          caissonDisko = inlineOf (layoutTop {
            integration = "caisson-disko";
            layout = luksLvmLayout;
            nixosModule = diskoNixosBase;
          });
          disko = inlineOf (layoutTop {
            integration = "disko";
            layout = luksLvmLayout;
          });
          darwin = inlineOf darwin.top;
          hjem = inlineOf hjem.top;
          microvm = inlineOf microvmHostTop;
        };
        # The registered configurations of the registered world, as
        # its `configs.` declaration events record them.
        fromRegistry = pkgs.lib.unique (
          builtins.map (event: { inherit (event) key origin; }) (
            builtins.filter (event: pkgs.lib.hasPrefix "configs." event.key) (declarationsOf registeredWorld)
          )
        );
        registeredAs = class: name: {
          key = "configs.${class}.${name}";
          origin = {
            project = "pinned-world";
            file = "tests/pinned-world/configs/${class}/${name}";
          };
        };
        sortByKey = builtins.sort (a: b: a.key < b.key);
      in
      recorded == expected
      &&
        sortByKey fromRegistry == sortByKey (
          [
            (registeredAs "structural" "pinned-world")
            (registeredAs "nixos" "minimal")
          ]
          ++ builtins.map (class: registeredAs class "registered") [
            "nixos"
            "homeManager"
            "hjem"
            "structural"
            "flake"
            "caisson-colmena"
            "caisson-disko"
            "disko"
            "caisson-facter"
            "facter"
            "terranix"
            "systemManager"
            "treefmt"
            "nvf"
            "nixvim"
            "topology"
            "kubenix"
            "nixidy"
            "nixosTest"
          ]
        )
      # The configuration given the entry registered as `minimal`
      # records that entry, not an inline module.
      &&
        pkgs.lib.unique (
          builtins.map (event: event.key) (
            builtins.filter (
              event:
              pkgs.lib.hasPrefix "configs." event.key
              && placeOf event == "system x86_64-linux / nixos given-an-entry"
            ) (declarationsOf registeredWorld)
          )
        ) == [ "configs.nixos.minimal" ];

    # Each configuration records how it selected its modules. The caisson top
    # above the NixOS configuration gives `moduleImports`, which
    # replaces the default, and the record holds where it gave it. The
    # NixOS configuration takes the default of its class, the entries
    # named `default`. The home-manager configuration inside it takes
    # the default of its class too, which holds what the NixOS
    # configuration adds for the home-manager configurations declared
    # inside it, with the name path of the NixOS configuration and the
    # file of caisson that adds it.
    selectionsRecordHowModulesWereChosen =
      let
        top = nixosConfigurationWithHomeManagerConfigurations.caisson.manifest;
        probe = top.children.system.x86_64-linux.children.nixos.probe;
        declared = probe.children.system.x86_64-linux.children.home-manager.declared;
        probePath = [
          {
            type = "system";
            name = "x86_64-linux";
          }
          {
            type = "nixos";
            name = "probe";
          }
        ];
      in
      top.moduleImports.act == "reset"
      && top.moduleImports.selected == [ ]
      && top.moduleImports.position.file == "tests/pinned-world/default.nix"
      && builtins.isInt top.moduleImports.position.line
      &&
        probe.moduleImports == {
          act = "default";
          position = null;
          default = [
            {
              key = "modules.nixos.caisson/default";
              level = null;
              file = null;
            }
          ];
          selected = [ "modules.nixos.caisson/default" ];
        }
      && declared.moduleImports.act == "default"
      &&
        declared.moduleImports.selected == [
          "modules.homeManager.caisson/default"
          "modules.homeManager.nixos-parent"
        ]
      &&
        builtins.elemAt declared.moduleImports.default 1 == {
          key = "modules.homeManager.nixos-parent";
          level = probePath;
          file = "modules/nixos/default/caisson";
        };

    # Each configuration records where each part of the stack it used
    # came from. Every configuration here is evaluated on the library
    # of the nixpkgs pin, through the `defaultEcosystemSrc` of the
    # composition. The NixOS configuration selects its module
    # collection with its `ecosystemSrc`, and the home-manager
    # configuration inside it selects home-manager the same way. The
    # caisson top resolves no ecosystem beside the library.
    ecosystemsRecordWhereEachPartCameFrom =
      let
        top = nixosConfigurationWithHomeManagerConfigurations.caisson.manifest;
        probe = top.children.system.x86_64-linux.children.nixos.probe;
        declared = probe.children.system.x86_64-linux.children.home-manager.declared;
        library = {
          from = "defaultEcosystemSrc";
          source = "nixpkgs";
        };
      in
      top.ecosystems == {
        nixpkgs-lib = library;
      }
      &&
        probe.ecosystems == {
          nixpkgs-lib = library;
          nixos = {
            from = "ecosystemSrc";
            source = "nixpkgs";
          };
        }
      &&
        declared.ecosystems == {
          nixpkgs-lib = library;
          home-manager = {
            from = "ecosystemSrc";
            source = "home-manager";
          };
        };

    # The configurations of the shared probe caisson tops record where each
    # ecosystem they resolved came from. `hiveLib` pins colmena and
    # disko under those names and selects nothing for them, so a colmena
    # configuration and a disko configuration of either integration
    # take the pinned source of that name. A NixOS configuration inside
    # them takes its module collection from the `nixos` of the `defaultEcosystemSrc`
    # of the composition. The darwin composition pins nix-darwin,
    # nixpkgs, home-manager and hjem under those names. The hjem
    # composition pins hjem
    # and selects its module collection as `hiveLib` does.
    ecosystemsRecordWhereEachIntegrationsPartsCameFrom =
      let
        pinned = source: {
          from = "dependencies";
          inherit source;
        };
        library = {
          from = "defaultEcosystemSrc";
          source = "nixpkgs";
        };
        colmena =
          (colmenaTop { probe-node = minimalNixosBase; })
          .caisson.manifest.children.caisson-colmena.colmenaHive;
        node = colmena.children.system.x86_64-linux.children.nixos.probe-node;
        upstreamColmena = upstreamHiveTop.caisson.manifest.children.colmena.colmenaHive;
        caissonDisko = layoutManifest "caisson-disko" (layoutTop {
          integration = "caisson-disko";
          layout = luksLvmLayout;
        });
        disko = layoutManifest "disko" (layoutTop {
          integration = "disko";
          layout = luksLvmLayout;
        });
        darwin = import ../darwin-system { inherit inputs; };
        family = darwin.familyManifest;
        familyChildren = family.children.system.${darwin.system}.children;
        hjem = import ../hjem-system { inherit inputs; };
      in
      colmena.ecosystems == {
        nixpkgs-lib = library;
        colmena = pinned "colmena";
      }
      && node.ecosystems.nixos == library
      && upstreamColmena.ecosystems.colmena == pinned "colmena"
      &&
        caissonDisko.ecosystems == {
          nixpkgs-lib = library;
          disko = pinned "disko";
        }
      && disko.ecosystems.disko == pinned "disko"
      &&
        family.ecosystems == {
          nixpkgs-lib = library;
          nix-darwin = pinned "nix-darwin";
          nixpkgs = pinned "nixpkgs";
        }
      && familyChildren.home-manager.probe.ecosystems.home-manager == pinned "home-manager"
      && familyChildren.hjem.probe.ecosystems.hjem == pinned "hjem"
      && hjem.standalone.caisson.manifest.ecosystems.hjem == pinned "hjem"
      && hjem.inner.ecosystems.hjem == pinned "hjem"
      && hjem.nixosManifest.ecosystems.nixos == library;

    # A selector that renames and drops configurations, with a note
    # saying so: the export record holds the published names alone,
    # each with the name path by the names the configurations are
    # declared under, the note, and the file that defines the
    # selector before the position of the `exportsTo` of the NixOS
    # integration.
    exportRecordFollowsTheSelector =
      let
        nixosConfiguration =
          lib:
          lib.caisson.nixos.mkConfiguration {
            ecosystemSrc = dependencies: dependencies.nixpkgs;
            configModule = minimalNixosBase;
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations = {
                nas-1 = nixosConfiguration lib;
                lab-3 = nixosConfiguration lib;
              };
              caisson.nixos.exported =
                configurations:
                lib.mapAttrs' (name: lib.nameValuePair "office-${name}") (
                  lib.filterAttrs (name: _: !lib.hasPrefix "lab-" name) configurations
                );
              caisson.nixos.exportNote = "office NixOS configurations take the site prefix; lab NixOS configurations stay unpublished";
            };
        };
        entry = top.caisson.manifest.exportRecord.nixosConfigurations.office-nas-1;
      in
      builtins.attrNames top.nixosConfigurations == [ "office-nas-1" ]
      && builtins.attrNames top.caisson.manifest.exportRecord.nixosConfigurations == [ "office-nas-1" ]
      &&
        entry.from.namePath == [
          {
            type = "system";
            name = "x86_64-linux";
          }
          {
            type = "nixos";
            name = "nas-1";
          }
        ]
      &&
        entry.notes
        == [ "office NixOS configurations take the site prefix; lab NixOS configurations stay unpublished" ]
      && builtins.length entry.code == 2
      && (builtins.elemAt entry.code 0).line == null
      && pkgs.lib.hasSuffix "/lib-overlays/nixos/default.nix" (builtins.elemAt entry.code 1).file;

    # The same NixOS configuration activates the home-manager
    # configurations inside it. It writes a system unit for the
    # home-manager configuration whose account it declares, which runs
    # as that user, and a user unit for the other home-manager
    # configuration, which runs only for that user. The script of each
    # unit runs the `activate` program of the activation package of its
    # home-manager configuration. The system of the NixOS configuration
    # evaluates with the units in it, which also checks the assertions
    # of the NixOS configuration.
    aNixosConfigurationActivatesTheHomeManagerConfigurationsInsideIt =
      let
        nixosConfig = nixosConfigurationWithHomeManagerConfigurations.nixosConfigurations.probe.config;
        declared = nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."declared@probe";
        undeclared = nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."undeclared@probe";
        systemUnit = nixosConfig.systemd.services.home-manager-declared;
        userUnit = nixosConfig.systemd.user.services.home-manager-undeclared;
        # The script of the unit runs `activate` of the activation
        # package of the home-manager configuration: the string
        # context of the script records that it refers to the
        # activation package, and the script runs an `activate`.
        runs =
          unit: homeManagerConfiguration:
          let
            script = unit.serviceConfig.ExecStart.text;
          in
          builtins.elem homeManagerConfiguration.activationPackage.drvPath (
            builtins.attrNames (builtins.getContext script)
          )
          && pkgs.lib.hasInfix "/activate" script;
      in
      systemUnit.serviceConfig.User == "declared"
      && systemUnit.unitConfig.RequiresMountsFor == "/home/declared"
      && runs systemUnit declared
      && !(runs systemUnit undeclared)
      && userUnit.unitConfig.ConditionUser == "undeclared"
      && runs userUnit undeclared
      && !(runs userUnit declared)
      && !(nixosConfig.systemd.services ? home-manager-undeclared)
      && !(nixosConfig.systemd.user.services ? home-manager-declared)
      && builtins.isString nixosConfig.system.build.toplevel.drvPath;

    # A home-manager configuration that leaves `caisson.useUserPackages`
    # unset installs its packages itself: home-manager's option
    # `submoduleSupport.externalPackageInstall` is false, the profile of
    # the packages is `~/.nix-profile`, the `activate` script installs
    # `home.path` into it, and the profile adapter says that the
    # activation sets both profiles. The NixOS configuration adds no
    # packages to the account, builds no `/etc/profiles/per-user/<user>`,
    # and links no `/etc/profile.d`.
    aHomeManagerConfigurationInstallsItsPackagesByDefault =
      let
        nixosConfig = nixosConfigurationWithHomeManagerConfigurations.nixosConfigurations.probe.config;
        homeManagerConfigurations =
          nixosConfigurationWithHomeManagerConfigurations.caisson.manifest.children.system.x86_64-linux.children.nixos.probe.children.system.x86_64-linux.children.home-manager;
        installsItsPackages =
          name: directory:
          let
            manifest = homeManagerConfigurations.${name};
            config = manifest.value.config;
            adapter = manifest.activation.profileAdapter manifest;
            inherit (manifest.outputs) activationPackage;
          in
          !config.submoduleSupport.externalPackageInstall
          && config.home.profileDirectory == "${directory}/.nix-profile"
          && pkgs.lib.hasInfix "INSTALL_CMD_ACTUAL" config.home.activation.installPackages.data
          && adapter.activate == "${activationPackage}/activate"
          &&
            adapter.profiles.generations.path
            == "\${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"
          && adapter.profiles.generations.holds.drvPath == activationPackage.drvPath
          && adapter.profiles.generations.setBy == "activation"
          && adapter.profiles.packages.path == "${directory}/.nix-profile"
          && adapter.profiles.packages.holds.drvPath == config.home.path.drvPath
          && adapter.profiles.packages.setBy == "activation";
      in
      installsItsPackages "declared" "/home/declared"
      && installsItsPackages "undeclared" "/home/undeclared"
      && nixosConfig.users.users.declared.packages == [ ]
      && !(nixosConfig.environment.etc ? "profiles/per-user/declared")
      && !(nixosConfig.environment.etc ? "profiles/per-user/undeclared")
      && !(builtins.elem "/etc/profile.d" nixosConfig.environment.pathsToLink);

    # A home-manager configuration that sets `caisson.useUserPackages`
    # leaves its packages to the NixOS configuration. home-manager's
    # option `submoduleSupport.externalPackageInstall` is true, so the
    # profile of the packages is `/etc/profiles/per-user/<user>`, and the
    # `activate` script removes `home-manager-path` from the profile in
    # the home directory instead of installing it. The NixOS
    # configuration adds `home.path` to the packages of the account it
    # declares, builds
    # `/etc/profiles/per-user/<user>` from `home.path` for the user
    # declared elsewhere, and links `/etc/profile.d`. The home-manager
    # configuration beside them that leaves the option unset installs
    # its packages itself, and the units of all three are as without the
    # option.
    aNixosConfigurationInstallsThePackagesOfAHomeManagerConfigurationThatSetsUseUserPackages =
      let
        nixosConfig = nixosConfigurationWithUserPackages.nixosConfigurations.probe.config;
        homeManagerConfigurations =
          nixosConfigurationWithUserPackages.caisson.manifest.children.system.x86_64-linux.children.nixos.probe.children.system.x86_64-linux.children.home-manager;
        configOf = name: homeManagerConfigurations.${name}.value.config;
        adapterOf =
          name: homeManagerConfigurations.${name}.activation.profileAdapter homeManagerConfigurations.${name};
        drvPaths = builtins.map (package: package.drvPath);
        installedByTheNixosConfiguration =
          name:
          let
            config = configOf name;
            adapter = adapterOf name;
            step = config.home.activation.installPackages.data;
          in
          config.submoduleSupport.externalPackageInstall
          && config.home.profileDirectory == "/etc/profiles/per-user/${name}"
          && pkgs.lib.hasInfix "nixProfileRemove home-manager-path" step
          && !(pkgs.lib.hasInfix "INSTALL_CMD" step)
          && adapter.profiles.packages.path == "/etc/profiles/per-user/${name}"
          && adapter.profiles.packages.holds.drvPath == config.home.path.drvPath
          && adapter.profiles.packages.setBy == "machine"
          && adapter.profiles.generations.setBy == "activation";
      in
      installedByTheNixosConfiguration "declared"
      && installedByTheNixosConfiguration "undeclared"
      && (adapterOf "plain").profiles.packages.setBy == "activation"
      && (configOf "plain").home.profileDirectory == "/home/plain/.nix-profile"
      && drvPaths nixosConfig.users.users.declared.packages == [ (configOf "declared").home.path.drvPath ]
      && nixosConfig.users.users.plain.packages == [ ]
      && !(nixosConfig.users.users ? undeclared)
      && nixosConfig.environment.etc ? "profiles/per-user/declared"
      &&
        drvPaths nixosConfig.environment.etc."profiles/per-user/undeclared".source.paths == [
          (configOf "undeclared").home.path.drvPath
        ]
      && !(nixosConfig.environment.etc ? "profiles/per-user/plain")
      && builtins.elem "/etc/profile.d" nixosConfig.environment.pathsToLink
      && nixosConfig.systemd.services ? home-manager-declared
      && nixosConfig.systemd.services ? home-manager-plain
      && nixosConfig.systemd.user.services ? home-manager-undeclared;

    # The home-manager configuration published as
    # `homeConfigurations."<user>@<host>"`, which a standalone
    # `home-manager switch` builds, is the home-manager configuration
    # the NixOS configuration activates: its activation package is the
    # package the unit of the NixOS configuration runs, with the option
    # set as without it. The marker of the NixOS configuration records
    # the digest of the `home.path` it
    # installed for each home-manager configuration that sets
    # `caisson.useUserPackages`, by the name of the marker file of that
    # home-manager configuration, and the drift step of that
    # home-manager configuration compares it with the `home.path` of
    # that home-manager configuration. The home-manager configuration
    # that leaves the option unset has no entry and no such comparison.
    aHomeManagerConfigurationThatSetsUseUserPackagesIsTheSameStandalone =
      let
        nixosConfig = nixosConfigurationWithUserPackages.nixosConfigurations.probe.config;
        homeManagerConfigurations =
          nixosConfigurationWithUserPackages.caisson.manifest.children.system.x86_64-linux.children.nixos.probe.children.system.x86_64-linux.children.home-manager;
        published = name: nixosConfigurationWithUserPackages.homeConfigurations."${name}@probe";
        unitRuns =
          unit: name:
          builtins.elem (published name).activationPackage.drvPath (
            builtins.attrNames (builtins.getContext unit.serviceConfig.ExecStart.text)
          );
        record = builtins.fromJSON nixosConfig.environment.etc."caisson/marker.json".text;
        digestOf = name: builtins.hashString "sha256" (toString (published name).config.home.path);
        step = name: (published name).config.home.activation.caissonDrift.data;
      in
      (published "declared").activationPackage.drvPath
      == homeManagerConfigurations.declared.outputs.activationPackage.drvPath
      && unitRuns nixosConfig.systemd.services.home-manager-declared "declared"
      && unitRuns nixosConfig.systemd.user.services.home-manager-undeclared "undeclared"
      && unitRuns nixosConfig.systemd.services.home-manager-plain "plain"
      &&
        builtins.attrNames record == [
          "identity"
          "profiles"
        ]
      &&
        record.profiles == {
          "home-manager-declared.json".packages = digestOf "declared";
          "home-manager-undeclared.json".packages = digestOf "undeclared";
        }
      && pkgs.lib.hasInfix "home-manager-declared.json" (step "declared")
      && pkgs.lib.hasInfix (digestOf "declared") (step "declared")
      && !(pkgs.lib.hasInfix ".profiles[$key][$name]" (step "plain"));

    # The same NixOS configuration writes the file
    # `/etc/caisson/marker.json`. The file holds the digest of the
    # system that the result of the childless evaluation of the NixOS
    # configuration builds.
    #
    # The system that the NixOS configuration builds has the units of
    # the home-manager configurations in it. So the digest in the file
    # is the digest of the system of the childless evaluation, and not
    # of the system that the NixOS configuration builds.
    #
    # Each home-manager configuration computes the same digest. The
    # activation of each home-manager configuration has a step that
    # compares that digest with the file. The script of the step must
    # therefore contain the digest and the path of the file.
    aNixosConfigurationRecordsWhatItsHomeManagerConfigurationsCompareAgainst =
      let
        nixosConfig = nixosConfigurationWithHomeManagerConfigurations.nixosConfigurations.probe.config;
        homeManagerConfigurations = [
          nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."declared@probe"
          nixosConfigurationWithHomeManagerConfigurations.homeConfigurations."undeclared@probe"
        ];
        record = builtins.fromJSON nixosConfig.environment.etc."caisson/marker.json".text;
        digest = record.identity;
        childless =
          nixosConfigurationWithHomeManagerConfigurations.caisson.manifest.children.system.x86_64-linux.children.nixos.probe.childlessManifest.outputs.toplevel;
        comparesAgainstIt =
          homeManagerConfiguration:
          let
            step = homeManagerConfiguration.config.home.activation.caissonDrift.data;
          in
          pkgs.lib.hasInfix digest step && pkgs.lib.hasInfix "/etc/caisson/marker.json" step;
      in
      builtins.attrNames record == [ "identity" ]
      && digest == builtins.hashString "sha256" childless.outPath
      && digest != builtins.hashString "sha256" nixosConfig.system.build.toplevel.outPath
      && builtins.all comparesAgainstIt homeManagerConfigurations;

    # A NixOS configuration can be evaluated alone, with
    # `mkTopConfiguration`, or declared inside another configuration,
    # under `caisson.nixos.configurations`. The parent here gives its
    # children nothing. The NixOS configuration must then have the same
    # evaluation result in each position: its system is the same
    # derivation.
    #
    # The NixOS configuration is declared inside a structural
    # configuration and inside a flake-parts configuration. Each parent
    # publishes it as `nixosConfigurations.probe`.
    aNixosConfigurationInsideAParentHasTheSameEvaluationResult =
      let
        probeArgs = {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule = {
            imports = [ minimalNixosBase ];
            networking.hostName = "probe";
          };
        };
        declaresTheProbe =
          { lib, ... }:
          {
            caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration probeArgs;
          };
        alone = hiveLib.caisson.nixos.mkTopConfiguration probeArgs;
        insideStructural =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule = declaresTheProbe;
          }).nixosConfigurations.probe;
        insideFlake =
          (hiveLib.caisson.flake-parts.mkTopConfiguration {
            configModule = declaresTheProbe;
          }).nixosConfigurations.probe;
        systemOf = configuration: configuration.config.system.build.toplevel.drvPath;
      in
      systemOf insideStructural == systemOf alone && systemOf insideFlake == systemOf alone;

    # A flake publishes its manifest as the output `caisson.manifest`,
    # as a structural caisson top does, with the export record of what it
    # publishes. The name path of the record's entry for the NixOS
    # configuration, followed from that manifest through `children`,
    # leads to the NixOS configuration the flake publishes.
    aFlakePublishesItsManifestWithTheExportRecord =
      let
        flake = hiveLib.caisson.flake-parts.mkTopConfiguration {
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.nixpkgs;
                configModule = minimalNixosBase;
              };
            };
        };
        top = flake.caisson.manifest;
        entry = top.exportRecord.nixosConfigurations.probe;
        reached = builtins.foldl' (
          manifest: segment: manifest.children.${segment.type}.${segment.name}
        ) top entry.from.namePath;
      in
      top.type == "flake-parts"
      &&
        reached.value.config.system.build.toplevel.drvPath
        == flake.nixosConfigurations.probe.config.system.build.toplevel.drvPath;

    # The NixOS integration records what `nixos-rebuild` reads from a
    # configuration: the system, the VM, the VM with a boot loader,
    # and the images. Each is a reference into `config.system.build`
    # of the real NixOS. The system and both VMs are derivations, and
    # NixOS offers at least one image.
    aNixosConfigurationRecordsItsSystemItsVmsAndItsImages =
      let
        outputs = nixosEvaluationLib.caisson.evalManifest.childlessManifest.outputs;
      in
      builtins.isString outputs.toplevel.drvPath
      && builtins.isString outputs.vm.drvPath
      && builtins.isString outputs.vmWithBootLoader.drvPath
      && builtins.isAttrs outputs.images
      && outputs.images != { };

    # The same for a home-manager configuration. A home-manager
    # configuration evaluated alone and the same home-manager
    # configuration declared inside a structural configuration build
    # the same activation package.
    #
    # A home-manager configuration declared inside a NixOS
    # configuration is given the home directory, the user ID and the
    # Nix package of the NixOS configuration, by modules that the NixOS
    # configuration passes to its home-manager configurations by
    # default. A home-manager configuration that passes `moduleImports`
    # selects its modules itself and gets none of them. Such a
    # home-manager configuration, inside a NixOS configuration, must
    # also build the same activation package as the home-manager
    # configuration evaluated alone.
    aHomeManagerConfigurationInsideAParentIsTheSameHomeManagerConfiguration =
      let
        homeManagerConfiguration = {
          ecosystemSrc = dependencies: dependencies.home-manager;
          configModule = {
            home.username = "probe";
            home.homeDirectory = "/home/probe";
            home.stateVersion = "25.05";
          };
        };
        alone = hiveLib.caisson.home-manager.mkTopConfiguration homeManagerConfiguration;
        insideStructural =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration homeManagerConfiguration;
              };
          }).homeConfigurations.probe;
        insideNixos =
          (hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations.parent = lib.caisson.nixos.mkConfiguration {
                  ecosystemSrc = dependencies: dependencies.nixpkgs;
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ minimalNixosBase ];
                      users.users.probe = {
                        isNormalUser = true;
                        home = "/home/probe";
                      };
                      caisson.home-manager.configurations.probe = lib.caisson.home-manager.mkConfiguration (
                        homeManagerConfiguration // { moduleImports = _modules: [ ]; }
                      );
                    };
                };
              };
          }).homeConfigurations."probe@parent";
        activationOf = configuration: configuration.activationPackage.drvPath;
      in
      activationOf insideStructural == activationOf alone
      && activationOf insideNixos == activationOf alone;

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

    # The same for a flake. A flake-parts configuration can be the
    # caisson top of a flake, or it can be declared inside another configuration,
    # under `caisson.flake-parts.configurations`. A flake declared
    # inside another publishes its NixOS configurations through its
    # parent.
    #
    # The flake here declares a NixOS configuration. The flake is
    # evaluated alone, inside a flake-parts configuration, and inside a
    # structural configuration. The parents give their children
    # nothing. Each of these caisson tops publishes the NixOS configuration as
    # `nixosConfigurations.probe`, and its system is the same
    # derivation in each.
    aFlakeInsideAParentPublishesTheSameNixosConfiguration =
      let
        flake = {
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.nixpkgs;
                configModule = {
                  imports = [ minimalNixosBase ];
                  networking.hostName = "probe";
                };
              };
            };
        };
        declaresTheFlake =
          { lib, ... }:
          {
            caisson.flake-parts.configurations.inner = lib.caisson.flake-parts.mkConfiguration flake;
          };
        alone = hiveLib.caisson.flake-parts.mkTopConfiguration flake;
        insideFlake = hiveLib.caisson.flake-parts.mkTopConfiguration {
          configModule = declaresTheFlake;
        };
        insideStructural = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = declaresTheFlake;
        };
        systemOf = top: top.nixosConfigurations.probe.config.system.build.toplevel.drvPath;
      in
      builtins.attrNames insideFlake.nixosConfigurations == [ "probe" ]
      && builtins.attrNames insideStructural.nixosConfigurations == [ "probe" ]
      && systemOf insideFlake == systemOf alone
      && systemOf insideStructural == systemOf alone;

    # An integration declares `top` when a configuration of it can be
    # a caisson top, and only then has `mkTopConfiguration`. A colmena
    # configuration and a disko configuration are declared inside
    # another configuration, so their integrations declare no
    # `top`.
    onlyAnIntegrationDeclaringTopHasMkTopConfiguration =
      hiveLib.caisson.nixos ? mkTopConfiguration
      && hiveLib.caisson.darwin ? mkTopConfiguration
      && hiveLib.caisson.home-manager ? mkTopConfiguration
      && hiveLib.caisson.hjem ? mkTopConfiguration
      && hiveLib.caisson.structural ? mkTopConfiguration
      && hiveLib.caisson.flake-parts ? mkTopConfiguration
      && !(hiveLib.caisson.caisson-colmena ? mkTopConfiguration)
      && !(hiveLib.caisson.caisson-disko ? mkTopConfiguration)
      && !(hiveLib.caisson.disko ? mkTopConfiguration);

    # A colmena configuration declared under the name `colmenaHive` inside
    # a caisson top fills the caisson top's `colmenaHive`. Its nodes are the NixOS
    # configurations declared inside it, which the caisson top also publishes
    # as `nixosConfigurations`, so the node of the hive and the
    # published NixOS configuration are the same evaluation result.
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
        nixosModule = {
          imports = [ minimalNixosBase ];
          networking.hostName = "probe";
        };
        top = colmenaTop { probe = nixosModule; };
        node = top.colmenaHive.nodes.probe;
        system = hiveLib.caisson.nixos.mkTopConfiguration {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule = nixosModule;
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

    # A node is a single evaluation result. A NixOS configuration
    # declared inside a colmena configuration whose children are
    # evaluated for two systems has an evaluation result for each
    # system, and the hive refuses it. The caisson top still publishes each
    # evaluation result as a NixOS configuration, and each evaluates,
    # so it is the hive that refuses them. When the children of the
    # colmena configuration are evaluated for a single system, the same
    # caisson top has a single node.
    colmenaRefusesNodesEvaluatedMoreThanOnce =
      let
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        twoSystemsLib = core.mkLib {
          dependencies = { inherit (inputs) nixpkgs colmena; };
          inherit systems;
          projects.caisson = inputs.caisson;
          defaultEcosystemSrc = dependencies: {
            nixpkgs-lib = dependencies.nixpkgs;
            nixos = dependencies.nixpkgs;
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
        topFor =
          childSystems:
          twoSystemsLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.forChildren.systems = childSystems;
                      caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                        configModule = minimalNixosBase;
                      };
                    };
                };
              };
          };
        both = topFor systems;
        one = topFor [ "x86_64-linux" ];
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
                caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                  ecosystemSrc = _dependencies: ecosystemSrc;
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
                caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
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
    # group can be declared wherever NixOS configurations are, as a
    # unit. The same group of NixOS configurations is declared under a
    # structural caisson top and inside a colmena configuration: each NixOS
    # configuration has the same evaluation result in both places, the
    # caisson top publishes the NixOS configurations under their names, and the
    # colmena configuration finds its nodes through the group, under
    # the same names.
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
              caisson.structural.configurations.hosts = group lib;
            };
        };
        deployed = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.structural.configurations.hosts = group lib;
                  };
              };
            };
        };
        drvOf = evaluated: evaluated.config.system.build.toplevel.drvPath;
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
    # NixOS configurations, and each group gives its NixOS
    # configurations modules, which is what colmena's `defaults` and
    # per-node modules are for. Two groups add different modules to the
    # default of the NixOS configurations declared inside them: the
    # NixOS configurations a, b and c get the first, d and e the
    # second. Each module also tags its NixOS configurations with the
    # name of the group, so `colmena apply --on @first` selects the
    # first group. Every node gets the module and the tag of its group
    # and not the other, and every NixOS configuration is a node of the
    # hive.
    structuralGroupsInsideColmenaGiveTheirNixosConfigurationsModules =
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
                caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
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
        nodeNames = [
          "a"
          "b"
          "c"
          "d"
          "e"
        ];
        groupOf = nodeName: hive.nodes.${nodeName}.config.environment.etc.group-name.text;
        tagged =
          tag: builtins.filter (nodeName: builtins.elem tag hive.deploymentConfig.${nodeName}.tags) nodeNames;
      in
      builtins.attrNames hive.nodes == nodeNames
      &&
        builtins.map groupOf nodeNames == [
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
    # caisson top publishes the nodes as NixOS configurations.
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

    # `nodes` is the nodes themselves: the NixOS configurations declared
    # inside the colmena configuration, read from the evaluation result
    # of the colmena configuration with its children, through
    # `unsafeCrossChildReferences`. Each node records the colmena configuration as the
    # level whose children it reads.
    colmenaUpstreamNodesAreTheNodes =
      let
        colmena = upstreamHiveTop.caisson.manifest.children.colmena.colmenaHive;
        alpha = colmena.children.system.x86_64-linux.children.nixos.alpha;
      in
      alpha.crossChildLevel != null
      && !alpha.crossChildLevel.childless
      && alpha.crossChildLevel.name == "colmenaHive"
      &&
        alpha.crossChildLevelPath == [
          {
            type = "colmena";
            name = "colmenaHive";
          }
        ];

    # The root composite, declared under the name `nixops4`, fills the
    # `nixops4` of the caisson top, the root NixOps4's command reads. A resource holding a
    # NixOS configuration becomes, through the NixOS adapter, an `exec`
    # resource of NixOps4's `local` provider that copies the toplevel of
    # that configuration and runs its `bin/apply switch` over SSH, to
    # the name of the resource as the host when nothing sets one. The
    # toplevel contains the `bin/apply` the `nixops4-apply` module
    # builds.
    nixops4RootEvaluatesEndToEnd =
      let
        top = nixops4TopWith {
          resources.probe.ssh.hostPublicKey = nixops4HostKey;
        } { probe = minimalNixosBase; };
        export = nixops4Export top.nixops4;
        resource = export.members.probe.resource;
        args = resource.inputs.args;
        evaluated =
          (nixops4RootManifest top).children.caisson-nixops4-resource.probe.value.config.nixos.configuration;
      in
      top.nixops4._type == "nixops4Component"
      && builtins.attrNames export.members == [ "probe" ]
      && resource.type == "exec"
      && resource.inputs.executable == pkgs.lib.getExe pkgs.bash
      && builtins.elemAt args 2 == "root@probe"
      && builtins.elemAt args 3 == "${evaluated.config.system.build.toplevel}"
      && pkgs.lib.hasInfix "$1/bin/apply switch" (builtins.elemAt args 1)
      && pkgs.lib.hasInfix "$out/bin/apply" evaluated.config.system.activatableSystemBuilderCommands
      && pkgs.lib.hasInfix nixops4HostKey (
        builtins.readFile (
          builtins.head (builtins.match ".*UserKnownHostsFile=([^ ]*) .*" (builtins.elemAt args 1))
        )
      );

    # A composite wires a resource to the outputs of another member
    # through `members`, and NixOps4 evaluates the root again with the
    # outputs it learns. The SSH settings change the command line as
    # they do in nixops4-nixos.
    nixops4ResourceReadsSiblingOutputs =
      let
        top = nixops4TopWith {
          root = nixops4AddressRoot;
          wiring = members: {
            probe = {
              ssh.host = members.address.outputs.stdout;
              ssh.hostPublicKey = nixops4HostKey;
              ssh.user = "deploy";
              ssh.opts = "-p 2222";
              copy.substituteOnDestination = false;
            };
          };
        } { probe = minimalNixosBase; };
        export = nixops4Export top.nixops4;
        args = export.members.probe.resource.inputs.args;
        script = builtins.elemAt args 1;
      in
      builtins.attrNames export.members == [
        "address"
        "probe"
      ]
      && builtins.elemAt args 2 == "deploy@stub"
      && pkgs.lib.hasInfix "sudo $1/bin/apply switch" script
      && pkgs.lib.hasInfix "'-p 2222'" script
      && !(pkgs.lib.hasInfix "--substitute-on-destination" script);

    # The shell that runs the deployment comes from the package set
    # caisson selects for the resource, inherited from the root
    # composite, for the deploying system: here a selection whose
    # `bash` is another shell.
    nixops4DeploysWithTheSelectedPackageSet =
      let
        top = nixops4TopWith {
          resources.probe.ssh.hostPublicKey = nixops4HostKey;
          defaultPkgs = pkgSets: pkgSets.default // { bash = pkgSets.default.dash; };
        } { probe = minimalNixosBase; };
      in
      (nixops4Export top.nixops4).members.probe.resource.inputs.executable == pkgs.lib.getExe pkgs.dash;

    # Composite and resource are two classes: a composite has no `type`
    # and a resource no `members`, and setting either is an error where
    # it is set rather than a member silently dropped.
    nixops4CompositeAndResourceAreTwoClasses =
      let
        evaluates = top: (builtins.tryEval (builtins.deepSeq (nixops4Export top.nixops4) true)).success;
        resourceTop =
          extra:
          nixops4TopWith {
            resources.probe = {
              ssh.hostPublicKey = nixops4HostKey;
            }
            // extra;
          } { probe = minimalNixosBase; };
      in
      evaluates (nixops4TopWith { } { })
      && !(evaluates (nixops4TopWith { root.type = "exec"; } { }))
      && evaluates (resourceTop { })
      && !(evaluates (resourceTop {
        members.extra = { };
      }));

    # The root composite is a deferred configuration declared at the
    # caisson top: the manifest of the caisson top holds its entry, and nothing declared
    # inside it is evaluated at flake time. Finalized, its manifest names the
    # args it takes: the deploying system and the outputs of its
    # resources, which are not cacheable unless a resource lists them.
    # Each manifest records where its args came from, not their values.
    nixops4RootIsDeferred =
      let
        top = nixops4TopWith {
          resources.probe = {
            ssh.hostPublicKey = nixops4HostKey;
            cacheableOutputs = [ "stdout" ];
          };
        } { probe = minimalNixosBase; };
        entry = nixops4Entry top;
        root = nixops4RootManifest top;
        needed = root.argsNeeded;
      in
      core.isDeferred entry
      && entry.type == "caisson-nixops4-composite"
      && entry.parent.childless
      &&
        nixops4ArgPathsOf needed == [
          [
            "outputValues"
            "probe"
            "stdout"
          ]
          [ "resourceProviderSystem" ]
        ]
      && needed.outputValues.probe.stdout.cacheable
      && needed.resourceProviderSystem.cacheable
      &&
        root.argsSource [
          "outputValues"
          "probe"
          "stdout"
        ] == "the probe"
      &&
        root.children.caisson-nixops4-resource.probe.argsSource [
          "outputValues"
          "stdout"
        ] == "the composite at the root";

    # An output NixOps4 has not passed fails where it is read, with the
    # text `caisson-deferred: needs outputValues.address.stdout`, and
    # the members that do not read it evaluate.
    nixops4MissingOutputFailsWhereRead =
      let
        top = nixops4TopWith {
          root = nixops4AddressRoot;
          wiring = members: {
            probe = {
              ssh.host = members.address.outputs.stdout;
              ssh.hostPublicKey = nixops4HostKey;
            };
          };
        } { probe = minimalNixosBase; };
        export = top.nixops4.rootFunction {
          resourceProviderSystem = "x86_64-linux";
          outputValues.probe.stdout = "stub";
        };
      in
      export.members.address.resource.type == "exec"
      && !(builtins.tryEval (builtins.elemAt export.members.probe.resource.inputs.args 2)).success;

    # A resource whose type depends on the output of another member
    # names its outputs once that output is known. Given the
    # output, it evaluates, with the type the output selects. Without
    # it, the outputs of the other members are still named.
    nixops4TypeDependsOnAnotherOutput =
      let
        top = nixops4TopWith {
          root =
            { lib, members, ... }:
            {
              imports = [ nixops4AddressRoot ];
              caisson.caisson-nixops4-resource.configurations.dependent =
                lib.caisson.caisson-nixops4-resource.mkConfiguration
                  {
                    configModule =
                      { providers, ... }:
                      let
                        file = members.address.outputs.stdout == "file";
                      in
                      {
                        providers.local = inputs.nixops4.modules.nixops4Provider.local;
                        type = if file then providers.local.file else providers.local.exec;
                        inputs =
                          if file then
                            {
                              name = "/run/probe";
                              contents = "";
                            }
                          else
                            { executable = "/bin/true"; };
                      };
                  };
            };
        } { };
        exportWith =
          stdout:
          top.nixops4.rootFunction {
            resourceProviderSystem = "x86_64-linux";
            outputValues = {
              address = { inherit stdout; };
              dependent = { };
            };
          };
        withoutOutputs = (nixops4Entry top).finalize {
          args.resourceProviderSystem = "x86_64-linux";
          argsSource = _: "the probe";
        };
      in
      (exportWith "file").members.dependent.resource.type == "file"
      && (exportWith "file").members.dependent.resource.outputsSkeleton == { }
      && builtins.attrNames (exportWith "exec").members.dependent.resource.outputsSkeleton == [ "stdout" ]
      && builtins.attrNames withoutOutputs.argsNeeded.outputValues.address == [ "stdout" ]
      && !(builtins.tryEval withoutOutputs.argsNeeded.outputValues.dependent).success;

    # The `members` argument of a native composite holds, for each
    # member, its outputs and its member path, from the args and the
    # names the members are declared under. A member's config is not
    # reachable through it.
    nixops4NativeMembersHoldOutputsAndPaths =
      let
        top = nixops4TopWith {
          root =
            { lib, members, ... }:
            {
              imports = [ nixops4AddressRoot ];
              options.seen = lib.mkOption { type = lib.types.raw; };
              config.seen = members;
            };
        } { };
        seen = (nixops4RootManifest top).value.config.seen;
      in
      builtins.attrNames seen.address == [
        "absoluteMemberPath"
        "outputs"
      ]
      && seen.address.absoluteMemberPath == [ "address" ]
      && seen.address.outputs.stdout == "stub";

    # A deployment that holds a resource with a state gives a program,
    # built for the system of the tool that asks, that reads the
    # outputs NixOps4 recorded. The program finds the resources that
    # hold state from the `state` option of each resource. A deployment
    # with no state gives none.
    nixops4RootDiscoversRecordedOutputs =
      let
        stateful = nixops4TopWith {
          root =
            { lib, ... }:
            {
              caisson.caisson-nixops4-resource.configurations.state =
                lib.caisson.caisson-nixops4-resource.mkConfiguration
                  {
                    configModule =
                      { providers, ... }:
                      {
                        providers.local = inputs.nixops4.modules.nixops4Provider.local;
                        type = providers.local.state_file;
                        inputs.name = "state.json";
                      };
                  };
            };
          resources.probe.ssh.hostPublicKey = nixops4HostKey;
          wiring = members: { probe.state = members.state; };
        } { probe = minimalNixosBase; };
        root = nixops4RootManifest stateful;
        discover = root.discoverArgs { system = "x86_64-linux"; };
      in
      (nixops4RootManifest (nixops4TopWith { } { })).discoverArgs { system = "x86_64-linux"; } == null
      && root.outputs.stateResources == [ [ "state" ] ]
      && (nixops4Export stateful.nixops4).members.probe.resource.state == [ "state" ]
      && discover.name == "caisson-nixops4-discover"
      && discover.system == "x86_64-linux";

    # A deferred configuration of another tool beside the root of a
    # NixOps4 deployment in one flake has a separate entry, publication,
    # args and discovery program, and each entry finalizes without the
    # other.
    nixops4BesideAnotherDeferredTool =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              imports = [ (lib.caisson.integrations.configurationsModuleFor [ "greeter" ]) ];
              caisson.greeter.configurations.hello = greeterConfiguration lib;
              caisson.caisson-nixops4-composite.configurations.nixops4 =
                lib.caisson.caisson-nixops4-composite.mkConfiguration
                  { configModule = nixops4AddressRoot; };
            };
        };
        greeter = top.caisson.manifest.children.greeter.hello;
        greeted = greeter.finalize {
          args.who = "caisson";
          argsSource = _: "the probe";
        };
      in
      core.isDeferred greeter
      && greeter.type == "greeter"
      && top.greetings.hello "world" == "hello world"
      && greeted.outputs.greeting == "hello caisson"
      && greeted.argsNeeded.who.cacheable
      && (greeted.discoverArgs { system = "x86_64-linux"; }).name == "greeter-discover"
      && (nixops4RootManifest top).discoverArgs { system = "x86_64-linux"; } == null
      && (nixops4Export top.nixops4).members.address.resource.type == "exec";

    # A provider is evaluated inside the component that declares it.
    # `getProviders` evaluates the root without outputs and builds the
    # providers the root declares, as NixOps4's `getProviders` does.
    nixops4ProvidersBuildWithoutOutputs =
      let
        top = nixops4TopWith {
          root.providers.local = inputs.nixops4.modules.nixops4Provider.local;
        } { };
        built = top.nixops4.getProviders { system = "x86_64-linux"; };
      in
      pkgs.lib.isDerivation built && pkgs.lib.hasPrefix "nixops-root-providers" built.name;

    # The upstream-compatible integration takes root modules as a
    # NixOps4 user writes them, `_class` included, and NixOps4 reads
    # the same export from it: a member that sets `type` is a resource,
    # any other a composite, to any depth. A member reads another
    # member's outputs through `members`.
    nixops4UpstreamRootEvaluates =
      let
        top = nixops4UpstreamTopWith { } [ nixops4UpstreamRoot ];
        export = nixops4Export top.nixops4;
        probe = export.members.probe.resource;
      in
      top.nixops4._type == "nixops4Component"
      &&
        builtins.attrNames export.members == [
          "address"
          "group"
          "probe"
        ]
      && export.members.address.resource.type == "exec"
      && builtins.attrNames export.members.group.members == [ "inner" ]
      && export.members.group.members.inner.resource.inputs.executable == "/bin/false"
      && builtins.elemAt probe.inputs.args 2 == "root@stub";

    # A member that imports nixops4-nixos gets its `nixos.module`
    # evaluated as a caisson NixOS configuration declared inside it, with the
    # `bin/apply` NixOps4 runs, and builds the system NixOS builds from
    # the same module and the `apply` module nixops4-nixos adds, named
    # for the member as caisson names it. The shell comes from the
    # package set caisson selects.
    nixops4UpstreamNixosIsACaissonConfiguration =
      let
        top = nixops4UpstreamTopWith { } [ nixops4UpstreamRoot ];
        probe = (nixops4Export top.nixops4).members.probe.resource;
        member = (nixops4RootManifest top).children.caisson-nixops4-resource.probe;
        nixosManifest = member.children.system.x86_64-linux.children.nixos.probe;
        upstream = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
          system = null;
          modules = [
            minimalNixosBase
            inputs.nixops4-nixos.modules.nixos.apply
            {
              nixpkgs.pkgs = pkgs;
              networking.hostName = "probe";
            }
          ];
        };
      in
      nixosManifest.type == "nixos"
      && probe.inputs.executable == pkgs.lib.getExe pkgs.bash
      && builtins.elemAt probe.inputs.args 3 == "${nixosManifest.value.config.system.build.toplevel}"
      && pkgs.lib.hasInfix "$out/bin/apply" nixosManifest.value.config.system.activatableSystemBuilderCommands
      &&
        nixosManifest.value.config.system.build.toplevel.drvPath
        == upstream.config.system.build.toplevel.drvPath;

    # The shell of a nixops4-nixos member comes from the package set
    # caisson selects for the nixops4 configuration, not from the
    # nixpkgs of nixops4-nixos: here a selection whose `bash` is
    # another shell.
    nixops4UpstreamDeploysWithTheSelectedPackageSet =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixops4.configurations.nixops4 = lib.caisson.nixops4.mkConfiguration {
                modules = [ nixops4UpstreamRoot ];
                defaultPkgs = pkgSets: pkgSets.default // { bash = pkgSets.default.dash; };
              };
            };
        };
      in
      (nixops4Export top.nixops4).members.probe.resource.inputs.executable == pkgs.lib.getExe pkgs.dash;

    # Every upstream composite reads the configs of its members through
    # its evaluation result with its children: each member records the
    # composite as the level whose children it reads.
    nixops4UpstreamMembersReadTheFullComposite =
      let
        root = nixops4RootManifest (nixops4UpstreamTopWith { } [ nixops4UpstreamRoot ]);
        probe = root.children.caisson-nixops4-resource.probe;
      in
      probe.crossChildLevel != null
      && !probe.crossChildLevel.childless
      && probe.crossChildLevel.name == "nixops4";

    # Upstream code reads a member through `members` and through
    # `config.members`: its outputs, and the member itself as the
    # resource that holds the state of another, which NixOps4's `state`
    # option accepts by its `absoluteMemberPath`.
    nixops4UpstreamReadsMembersAsUpstreamDoes =
      let
        top = nixops4UpstreamTopWith { } [
          (
            {
              providers,
              members,
              config,
              ...
            }:
            {
              providers.local = inputs.nixops4.modules.nixops4Provider.local;
              members.state = {
                type = providers.local.state_file;
                inputs.name = "state.json";
              };
              members.address = {
                type = providers.local.exec;
                inputs.executable = "/bin/true";
              };
              members.memo = {
                type = providers.local.memo;
                state = members.state;
                inputs.initialize_with = config.members.address.outputs.stdout;
              };
              members.group.members.echo = {
                type = providers.local.exec;
                inputs.executable = "/bin/echo";
                inputs.args = [ members.address.outputs.stdout ];
              };
            }
          )
        ];
        export = nixops4Export top.nixops4;
        root = nixops4RootManifest top;
      in
      export.members.memo.resource.state == [ "state" ]
      && export.members.memo.resource.inputs.initialize_with == "stub"
      && export.members.group.members.echo.resource.inputs.args == [ "stub" ]
      && root.children.caisson-nixops4-resource.memo.value.config.absoluteMemberPath == [ "memo" ]
      && root.outputs.stateResources == [ [ "state" ] ];

    # A member that sets `type` and declares members is refused, where
    # NixOps4 drops the members.
    nixops4UpstreamRefusesAResourceWithMembers =
      let
        evaluates = top: (builtins.tryEval (builtins.deepSeq (nixops4Export top.nixops4) true)).success;
        rootWith =
          extra:
          { providers, ... }:
          {
            providers.local = inputs.nixops4.modules.nixops4Provider.local;
            members.probe = {
              type = providers.local.exec;
              inputs.executable = "/bin/true";
            }
            // extra;
          };
      in
      evaluates (nixops4UpstreamTopWith { } [ (rootWith { }) ])
      && !(evaluates (nixops4UpstreamTopWith { } [ (rootWith { members.extra = { }; }) ]));

    # The allow-list of the nixops4 configuration says which outputs a
    # tool may cache, by member path; every other output is not
    # cacheable.
    nixops4UpstreamCacheableOutputsAreAllowListed =
      let
        top = nixops4UpstreamTopWith {
          cacheableOutputs."group.inner" = [ "stdout" ];
        } [ nixops4UpstreamRoot ];
        needed = (nixops4RootManifest top).argsNeeded;
      in
      needed.outputValues.group.inner.stdout.cacheable && !needed.outputValues.address.stdout.cacheable;

    # Native composites nest to any depth. Each composite finalizes its
    # members with their part of its args: its member path, the
    # `members` argument of each composite, the `argsSource` of each
    # member, the args the root names and the export all follow the
    # nesting. The `members` argument holds, for a composite member, the
    # outputs of its members by name. The root collects the state
    # resources of every composite inside it, each once, and only the root gives a
    # discovery program.
    nixops4NestedCompositesFollowTheNesting =
      let
        top = nixops4RootTopWith (
          { lib, members, ... }:
          {
            imports = [ nixops4SeesMembers ];
            caisson.caisson-nixops4-resource.configurations.state = nixops4StateFile lib;
            caisson.caisson-nixops4-resource.configurations.m = nixops4Exec lib { state = members.state; };
            caisson.caisson-nixops4-composite.configurations.a = nixops4Composite lib (
              { lib, members, ... }:
              {
                imports = [ nixops4SeesMembers ];
                caisson.caisson-nixops4-resource.configurations.s = nixops4StateFile lib;
                caisson.caisson-nixops4-resource.configurations.w = nixops4Exec lib { state = members.s; };
                caisson.caisson-nixops4-resource.configurations.w2 = nixops4Exec lib { state = members.s; };
                caisson.caisson-nixops4-composite.configurations.b = nixops4Composite lib (
                  { lib, ... }:
                  {
                    imports = [ nixops4SeesMembers ];
                    caisson.caisson-nixops4-resource.configurations.r = nixops4Exec lib {
                      cacheableOutputs = [ "stdout" ];
                    };
                  }
                );
              }
            );
          }
        );
        root = nixops4RootManifest top;
        export = nixops4Export top.nixops4;
        a = root.children.caisson-nixops4-composite.a;
        b = a.children.caisson-nixops4-composite.b;
        r = b.children.caisson-nixops4-resource.r;
        discover = root.discoverArgs { system = "x86_64-linux"; };
      in
      [
        root.outputs.path
        a.outputs.path
        b.outputs.path
        r.value.config.absoluteMemberPath
      ] == [
        [ ]
        [ "a" ]
        [
          "a"
          "b"
        ]
        [
          "a"
          "b"
          "r"
        ]
      ]
      && root.value.config.seen.a.absoluteMemberPath == [ "a" ]
      && root.value.config.seen.a.outputs.b.r.stdout == "stub"
      && root.value.config.seen.a.outputs.w.stdout == "stub"
      && a.value.config.seen.b.outputs.r.stdout == "stub"
      &&
        b.value.config.seen.r == {
          absoluteMemberPath = [
            "a"
            "b"
            "r"
          ];
          outputs.stdout = "stub";
        }
      && a.argsSource [ ] == "the composite at the root"
      && b.argsSource [ ] == "the composite at a"
      && r.argsSource [ ] == "the composite at a.b"
      &&
        nixops4ArgPathsOf root.argsNeeded == [
          [
            "outputValues"
            "a"
            "b"
            "r"
            "stdout"
          ]
          [
            "outputValues"
            "a"
            "w"
            "stdout"
          ]
          [
            "outputValues"
            "a"
            "w2"
            "stdout"
          ]
          [
            "outputValues"
            "m"
            "stdout"
          ]
          [ "resourceProviderSystem" ]
        ]
      && root.argsNeeded.outputValues.a.b.r.stdout.cacheable
      && !root.argsNeeded.outputValues.a.w.stdout.cacheable
      && export.members.a.members.b.members.r.resource.type == "exec"
      &&
        export.members.a.members.w.resource.state == [
          "a"
          "s"
        ]
      &&
        root.outputs.stateResources == [
          [
            "a"
            "s"
          ]
          [ "state" ]
        ]
      && a.discoverArgs { system = "x86_64-linux"; } == null
      && pkgs.lib.hasInfix "states=(a.s state)" discover.text;

    # A NixOS configuration declared inside a resource inside a nested
    # composite is deployed by that resource, as a NixOS configuration
    # declared inside a resource of the root is.
    nixops4NixosConfigurationInsideANestedComposite =
      let
        top = nixops4RootTopWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.site = nixops4Composite lib (
              { lib, ... }:
              {
                caisson.caisson-nixops4-resource.configurations.web =
                  lib.caisson.caisson-nixops4-resource.mkConfiguration
                    {
                      configModule =
                        { lib, ... }:
                        {
                          ssh.hostPublicKey = nixops4HostKey;
                          caisson.nixos.configurations.web = lib.caisson.nixos.mkConfiguration {
                            configModule = minimalNixosBase;
                          };
                        };
                    };
              }
            );
          }
        );
        args = (nixops4Export top.nixops4).members.site.members.web.resource.inputs.args;
        web =
          (nixops4RootManifest top)
          .children.caisson-nixops4-composite.site.children.caisson-nixops4-resource.web;
        nixosManifest = web.children.system.x86_64-linux.children.nixos.web;
      in
      web.value.config.absoluteMemberPath == [
        "site"
        "web"
      ]
      && builtins.elemAt args 2 == "root@web"
      && builtins.elemAt args 3 == "${nixosManifest.value.config.system.build.toplevel}";

    # Which members a composite has, and whether each is a composite or
    # a resource, may not depend on its members or on their outputs:
    # the composite that reads them there is refused with an error that
    # names it, in place of an infinite recursion. Reading `members`
    # anywhere else stays allowed. tests/deferred-errors reads the text.
    nixops4MembersDecidedFromOutputsAreRefused =
      let
        argsNeededOf = top: (nixops4RootManifest top).argsNeeded;
        native = nixops4RootTopWith (
          { lib, members, ... }:
          {
            imports = [ nixops4AddressRoot ];
            caisson.caisson-nixops4-resource.configurations = lib.optionalAttrs (
              members.address.outputs.stdout == "more"
            ) { extra = nixops4Exec lib { }; };
          }
        );
        nested = nixops4RootTopWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.a = nixops4Composite lib (
              { lib, members, ... }:
              {
                caisson.caisson-nixops4-resource.configurations = lib.optionalAttrs (members ? x) {
                  x = nixops4Exec lib { };
                };
              }
            );
          }
        );
        upstreamNames = nixops4UpstreamTopWith { } [
          (
            { providers, config, ... }:
            {
              providers.local = inputs.nixops4.modules.nixops4Provider.local;
              members = {
                address = {
                  type = providers.local.exec;
                  inputs.executable = "/bin/true";
                };
              }
              // (if config.members.address.outputs.stdout == "more" then { extra = { }; } else { });
            }
          )
        ];
        upstreamKind = nixops4UpstreamTopWith { } [
          (
            { providers, members, ... }:
            {
              providers.local = inputs.nixops4.modules.nixops4Provider.local;
              members.address = {
                type = providers.local.exec;
                inputs.executable = "/bin/true";
              };
              members.dynamic =
                if members.address.outputs.stdout == "resource" then
                  { type = providers.local.exec; }
                else
                  { members.inner.type = providers.local.exec; };
            }
          )
        ];
      in
      nixops4Fails (argsNeededOf native)
      && nixops4Fails (argsNeededOf nested)
      && nixops4Fails (argsNeededOf upstreamNames)
      && nixops4Fails (argsNeededOf upstreamKind)
      && !(nixops4Fails (argsNeededOf (nixops4TopWith { root = nixops4AddressRoot; } { })));

    # A resource whose `outputsSkeleton` reads the outputs of that
    # resource is
    # refused with an error that names it, in place of an infinite
    # recursion. tests/deferred-errors reads the text.
    nixops4OutputsNamedFromOwnOutputsAreRefused =
      let
        top = nixops4RootTopWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-resource.configurations.selfish = nixops4Exec lib (
              { config, ... }:
              {
                outputsSkeleton = lib.mkForce (
                  {
                    stdout = { };
                  }
                  // lib.optionalAttrs (config.outputs.stdout == "more") { extra = { }; }
                );
              }
            );
          }
        );
      in
      nixops4Fails (nixops4RootManifest top).argsNeeded;

    # A name declared both as a composite and as a resource is refused,
    # since NixOps4 holds one member under a name.
    nixops4OneMemberUnderAName =
      nixops4Fails
        (nixops4RootManifest (
          nixops4RootTopWith (
            { lib, ... }:
            {
              caisson.caisson-nixops4-resource.configurations.x = nixops4Exec lib { };
              caisson.caisson-nixops4-composite.configurations.x = nixops4Composite lib { };
            }
          )
        )).argsNeeded;

    # A flake publishes one root as `nixops4`: two roots, declared side
    # by side or in two groups, are refused, and so is a root declared
    # under another name. tests/deferred-errors reads the text.
    nixops4OneRootPerFlake =
      let
        topWith =
          module:
          hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule = module;
          };
        rootIn =
          lib:
          lib.caisson.structural.mkConfiguration {
            configModule.caisson.caisson-nixops4-composite.configurations.nixops4 =
              nixops4Composite lib nixops4AddressRoot;
          };
      in
      nixops4Fails
        (topWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.nixops4 = nixops4Composite lib nixops4AddressRoot;
            caisson.nixops4.configurations.nixops4 = lib.caisson.nixops4.mkConfiguration { };
          }
        )).nixops4._type
      &&
        nixops4Fails
          (topWith (
            { lib, ... }:
            {
              caisson.structural.configurations.one = rootIn lib;
              caisson.structural.configurations.two = rootIn lib;
            }
          )).nixops4._type
      &&
        nixops4Fails
          (topWith (
            { lib, ... }:
            {
              caisson.caisson-nixops4-composite.configurations.deploy = nixops4Composite lib nixops4AddressRoot;
            }
          )).nixops4._type;

    # A root declared inside a NixOS configuration, which is evaluated
    # per system, is published as `nixops4` when the NixOS configuration
    # is evaluated for a single system. Its entry is in the manifest for
    # that system.
    nixops4RootInsideANixosConfiguration =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.deployer = lib.caisson.nixos.mkConfiguration {
                configModule = {
                  imports = [ minimalNixosBase ];
                  caisson.caisson-nixops4-composite.configurations.nixops4 = nixops4Composite lib nixops4AddressRoot;
                };
              };
            };
        };
        entry =
          top.caisson.manifest.children.system.x86_64-linux.children.nixos.deployer.children.caisson-nixops4-composite.nixops4;
      in
      core.isDeferred entry
      && entry.parent.type == "nixos"
      && (nixops4Export top.nixops4).members.address.resource.type == "exec";

    # A deferred configuration whose parent does not finalize it stays
    # an entry in the children of that parent, for a tool to finalize:
    # a resource declared at the caisson top, and a composite declared inside
    # a resource. Neither has a composite above it, so each is at the
    # root of its member paths, and neither is published.
    nixops4EntriesAParentDoesNotFinalize =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-nixops4-resource.configurations.lone = nixops4Exec lib { };
              caisson.caisson-nixops4-composite.configurations.nixops4 = nixops4Composite lib (
                { lib, ... }:
                {
                  caisson.caisson-nixops4-resource.configurations.holder = nixops4Exec lib {
                    caisson.caisson-nixops4-composite.configurations.inner = nixops4Composite lib nixops4AddressRoot;
                  };
                }
              );
            };
        };
        finalizeWith =
          entry: outputValues:
          entry.finalize {
            args = {
              resourceProviderSystem = "x86_64-linux";
              inherit outputValues;
            };
            argsSource = _: "the probe";
          };
        lone = top.caisson.manifest.children.caisson-nixops4-resource.lone;
        inner =
          (nixops4RootManifest top)
          .children.caisson-nixops4-resource.holder.children.caisson-nixops4-composite.inner;
        loneFinalized = finalizeWith lone { stdout = "out"; };
        innerFinalized = finalizeWith inner { address.stdout = "out"; };
      in
      core.isDeferred lone
      && core.isDeferred inner
      && loneFinalized.outputs.path == [ ]
      && loneFinalized.outputs.export.resource.type == "exec"
      && innerFinalized.outputs.path == [ ]
      && innerFinalized.outputs.export.members.address.resource.type == "exec"
      &&
        builtins.attrNames top == [
          "caisson"
          "checks"
          "libOverlays"
          "modules"
          "nixops4"
          "pkgOverlays"
        ];

    # `getProviders` finalizes the root without outputs, so a provider
    # of the root configured from an output fails, as it does upstream.
    # It builds the providers of the root alone, as upstream collects
    # them, and leaves out the providers a composite declared inside the
    # root declares.
    nixops4ProvidersOfTheRootAlone =
      let
        providersOf =
          top:
          builtins.fromJSON (
            builtins.elemAt (pkgs.lib.splitString "\n"
              (top.nixops4.getProviders { system = "x86_64-linux"; }).text
            ) 1
          );
        fromOutputs = nixops4RootTopWith (
          { members, ... }:
          {
            imports = [ nixops4AddressRoot ];
            providers.reader = {
              executable = "/bin/reader";
              args = [ members.address.outputs.stdout ];
              resourceTypes = { };
            };
          }
        );
        nested = nixops4RootTopWith (
          { lib, ... }:
          {
            providers.root = {
              executable = "/bin/root";
              resourceTypes = { };
            };
            caisson.caisson-nixops4-composite.configurations.sub = nixops4Composite lib {
              providers.nested = {
                executable = "/bin/nested";
                resourceTypes = { };
              };
            };
          }
        );
      in
      nixops4Fails (providersOf fromOutputs)
      &&
        providersOf nested == {
          root = {
            executable = "/bin/root";
            args = [ ];
          };
        };

    # Upstream composites nest to any depth, as native ones do: the
    # member paths, the args the root names, the allow-list by member
    # path, and a member reading the output of a member two levels
    # down.
    nixops4UpstreamCompositesFollowTheNesting =
      let
        top = nixops4UpstreamTopWith { cacheableOutputs."g.h.r" = [ "stdout" ]; } [
          (
            { providers, members, ... }:
            {
              providers.local = inputs.nixops4.modules.nixops4Provider.local;
              members.g.members.h.members.r = {
                type = providers.local.exec;
                inputs.executable = "/bin/true";
              };
              members.g.members.reader = {
                type = providers.local.exec;
                inputs.executable = "/bin/echo";
                inputs.args = [ members.g.members.h.members.r.outputs.stdout ];
              };
            }
          )
        ];
        root = nixops4RootManifest top;
        r =
          root.children.caisson-nixops4-composite.g.children.caisson-nixops4-composite.h.children.caisson-nixops4-resource.r;
      in
      nixops4ArgPathsOf root.argsNeeded == [
        [
          "outputValues"
          "g"
          "h"
          "r"
          "stdout"
        ]
        [
          "outputValues"
          "g"
          "reader"
          "stdout"
        ]
        [ "resourceProviderSystem" ]
      ]
      && root.argsNeeded.outputValues.g.h.r.stdout.cacheable
      && !root.argsNeeded.outputValues.g.reader.stdout.cacheable
      &&
        r.value.config.absoluteMemberPath == [
          "g"
          "h"
          "r"
        ]
      && r.crossChildLevel.name == "h"
      && (nixops4Export top.nixops4).members.g.members.reader.resource.inputs.args == [ "stub" ];

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
    # configuration declared under the name of that output,
    # `colmenaHive`, is published there.
    colmenaHiveIsTheConfigurationNamedForIt =
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

    # A NixOS configuration installed onto a caisson-disko layout gets
    # the file systems, boot settings and swap the layout produces, and
    # nothing of disko: it has no `disko` option and no disko scripts.
    # It builds the system NixOS builds from the NixOS module of disko
    # and the same layout. The NixOS configuration `nas-1` inside the
    # layout `nas-1` is published as `nixosConfigurations.nas-1`, beside
    # `diskoConfigurations.nas-1`.
    caissonDiskoNixosConfigurationsGetTheLayoutsSettings =
      let
        top = layoutTop {
          integration = "caisson-disko";
          layout = luksLvmLayout;
          nixosModule = diskoNixosBase;
        };
        installed = top.nixosConfigurations.nas-1;
        upstream = upstreamDiskoNixosConfiguration luksLvmLayout;
      in
      builtins.attrNames top.nixosConfigurations == [ "nas-1" ]
      && builtins.attrNames top.diskoConfigurations == [ "nas-1" ]
      && !(installed.options ? disko)
      && !(installed.config.system.build ? formatScript)
      && installed.config.fileSystems."/".device == upstream.config.fileSystems."/".device
      && installed.config.system.build.toplevel.drvPath == upstream.config.system.build.toplevel.drvPath;

    # A caisson-disko layout is published in the form disko's command
    # reads. The evaluator of disko, given the published layout, makes
    # the format script it makes from the layout as written, and the
    # `scripts` output of the layout is that script too.
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

    # A layout with no NixOS configuration installed onto it is
    # published as a layout and nothing else.
    caissonDiskoLayoutsNeedNoNixosConfiguration =
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
          nixosModule = diskoNixosBase;
        };
        fails = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      fails top.diskoConfigurations.nas-1 && fails top.nixosConfigurations.nas-1.config.fileSystems;

    # A disko configuration is a layout with no NixOS configuration, as
    # the standalone form of disko has it. It is published as
    # `diskoConfigurations.nas-1`, with no NixOS configuration beside
    # it, and both
    # the evaluator of disko given the published layout and the
    # `scripts` output of the layout make the format script disko makes from the
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
                    diskoNixosBase
                  ];
                };
              };
            };
        };
        nas-1 = top.nixosConfigurations.nas-1;
        upstream = upstreamDiskoNixosConfiguration luksLvmLayout;
        installed = nas-1.extendModules {
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
      && nas-1.config.disko.devices.disk ? main
      && nas-1.config.system.build.toplevel.drvPath == upstream.config.system.build.toplevel.drvPath
      &&
        nas-1.config.system.build.formatScript.drvPath == upstream.config.system.build.formatScript.drvPath
      && installed.config.disko.devices.disk.main.device == "/dev/vdz";

    # disko's install test extends a NixOS configuration that imports
    # the NixOS module of disko. A NixOS configuration that selects
    # caisson's `disko` NixOS module builds the install test that a
    # NixOS configuration evaluated from disko's module and the same
    # layout builds.
    #
    # disko's image builder, `diskoImages` and `diskoImagesScript`, fails
    # to evaluate at the pinned disko and nixpkgs for a NixOS
    # configuration with no caisson: disko passes `vmTools` a tree of kernel modules as its
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
                    diskoNixosBase
                  ];
                };
              };
            };
        };
        build = top.nixosConfigurations.nas-1.config.system.build;
        upstream = (upstreamDiskoNixosConfiguration luksLvmLayout).config.system.build;
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

    # A caisson-disko layout can have several NixOS configurations
    # installed onto it, such as a server and its rescue system. Each
    # is published under the name it is declared with, and each gets
    # the file systems of the layout.
    caissonDiskoLayoutsHoldSeveralNixosConfigurations =
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
                      _hostName: lib.caisson.nixos.mkConfiguration { configModule = diskoNixosBase; }
                    );
                  };
              };
            };
        };
        upstream = upstreamDiskoNixosConfiguration luksLvmLayout;
        rootOf = evaluated: evaluated.config.fileSystems."/".device;
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
    # NixOS configuration installed onto it, so the NixOS configuration
    # `nas-1` is the node
    # `nas-1` of the hive, and the caisson top publishes it as
    # `nixosConfigurations.nas-1` beside `diskoConfigurations.nas-1`.
    diskoLayoutsInsideColmenaAreNodes =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ luksLvmLayout ];
                          caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                            configModule = diskoNixosBase // {
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

    # The nodes of a colmena configuration are the NixOS configurations
    # with no other NixOS configuration between them and the colmena
    # configuration. `nas-1`, inside a structural group and a disk
    # layout, is a node with colmena's deployment options. `plain` is a
    # node declared directly. A NixOS configuration declared inside a
    # node, `image` inside `nas-1` and `guest` inside `plain`, belongs to
    # that node: it is not a node of the hive, it has no deployment
    # options, and `image` does not get the file systems of the layout.
    # The caisson top still publishes all four as NixOS configurations.
    nixosConfigurationsInsideANodeAreNotNodes =
      let
        nested =
          lib: hostName:
          lib.caisson.nixos.mkConfiguration {
            configModule = {
              imports = [ minimalNixosBase ];
              networking.hostName = hostName;
            };
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.structural.configurations.rack = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule =
                        { lib, ... }:
                        {
                          caisson.caisson-disko.configurations.nas-1 = lib.caisson.caisson-disko.mkConfiguration {
                            configModule =
                              { lib, ... }:
                              {
                                imports = [ luksLvmLayout ];
                                caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                                  configModule =
                                    { lib, ... }:
                                    diskoNixosBase
                                    // {
                                      networking.hostName = "nas-1";
                                      caisson.nixos.configurations.image = nested lib "image";
                                    };
                                };
                              };
                          };
                        };
                    };
                    caisson.nixos.configurations.plain = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ minimalNixosBase ];
                          networking.hostName = "plain";
                          caisson.nixos.configurations.guest = nested lib "guest";
                        };
                    };
                  };
              };
            };
        };
        hive = top.colmenaHive;
        published = top.nixosConfigurations;
      in
      builtins.attrNames hive.nodes == [
        "nas-1"
        "plain"
      ]
      &&
        builtins.attrNames published == [
          "guest"
          "image"
          "nas-1"
          "plain"
        ]
      && hive.nodes.nas-1.options ? deployment
      && hive.deploymentConfig.nas-1.targetHost == "nas-1"
      && hive.nodes.plain.options ? deployment
      && !(published.image.options ? deployment)
      && !(published.guest.options ? deployment)
      && published.nas-1.config.fileSystems ? "/boot"
      && !(published.image.config.fileSystems ? "/boot")
      && published.image.config.fileSystems."/".fsType == "tmpfs";

    # What a level gives through `caisson.forNearestChildren` is added
    # to the nearest NixOS configurations declared inside it, through a
    # structural group and through a disk layout, and not to a NixOS
    # configuration declared inside one of them. What it gives through
    # `caisson.forChildren` is added to the NixOS configurations declared
    # inside it, the nested ones included, since none of them passes
    # `moduleImports`. The default account of a nearest configuration
    # records the addition with the level and the file that gave it and
    # with `nearest = true`, after the additions given through
    # `caisson.forChildren`. The default account of a NixOS configuration
    # declared inside a nearest configuration records none.
    forNearestChildrenConnectsOnce =
      let
        marker = name: {
          environment.etc.${name}.text = name;
        };
        nixosConfiguration =
          lib: hostName: base: inner:
          lib.caisson.nixos.mkConfiguration {
            configModule =
              { lib, ... }:
              {
                imports = [ base ];
                networking.hostName = hostName;
              }
              // (
                if inner == null then
                  { }
                else
                  {
                    caisson.nixos.configurations.${inner} = nixosConfiguration lib inner minimalNixosBase null;
                  }
              );
          };
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [ (marker "nearest") ];
              caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [ (marker "every") ];
              caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.a = nixosConfiguration lib "a" minimalNixosBase "a-inner";
                  };
              };
              caisson.caisson-disko.configurations.layout = lib.caisson.caisson-disko.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ luksLvmLayout ];
                    caisson.nixos.configurations.b = nixosConfiguration lib "b" diskoNixosBase "b-inner";
                  };
              };
            };
        };
        published = top.nixosConfigurations;
        has = name: publishedName: published.${publishedName}.config.environment.etc ? ${name};
        names = [
          "a"
          "a-inner"
          "b"
          "b-inner"
        ];
        manifest = top.caisson.manifest;
        b = manifest.children.caisson-disko.layout.children.system.x86_64-linux.children.nixos.b;
        bInner = b.children.system.x86_64-linux.children.nixos.b-inner;
        shapeOf =
          account:
          builtins.map (entry: {
            inherit (entry) level;
            nearest = entry.nearest or false;
          }) account.default;
        topLevel = [ ];
        layoutLevel = [
          {
            type = "caisson-disko";
            name = "layout";
          }
        ];
      in
      builtins.attrNames published == names
      &&
        builtins.map (has "nearest") names == [
          true
          false
          true
          false
        ]
      && builtins.all (has "every") names
      # The default entry of caisson, the addition the caisson top gives through
      # `caisson.forChildren`, the addition the caisson top gives the nearest
      # NixOS configurations, and the layout entry of caisson-disko,
      # which is an addition for the nearest NixOS configurations too.
      &&
        shapeOf b.moduleImports == [
          {
            level = null;
            nearest = false;
          }
          {
            level = topLevel;
            nearest = false;
          }
          {
            level = topLevel;
            nearest = true;
          }
          {
            level = layoutLevel;
            nearest = true;
          }
        ]
      &&
        builtins.elemAt b.moduleImports.default 3 == {
          key = "modules.nixos.caisson-disko-layout";
          level = layoutLevel;
          file = "modules/caisson-disko/default";
          nearest = true;
        }
      &&
        shapeOf bInner.moduleImports == [
          {
            level = null;
            nearest = false;
          }
          {
            level = topLevel;
            nearest = false;
          }
        ];

    # A host that selects caisson's `microvm-host` NixOS module runs
    # the guests of its caisson-microvm configuration, `a`, `b` and
    # `c`, and its microvm configuration `upstream`. Each is a
    # `microvm.vms.<guest>` whose `evaluatedConfig` is caisson's
    # evaluation of the guest, the configuration the caisson top publishes as
    # `nixosConfigurations.<guest>`. Each guest of `pool` gets the
    # `autostart` and `restartIfChanged` of `pool` as
    # `microvm.vms.<guest>.autostart` and
    # `microvm.vms.<guest>.restartIfChanged`.
    caissonMicrovmGuestsRunOnTheirHost =
      let
        top = microvmHostTop;
        vms = top.nixosConfigurations.host.config.microvm.vms;
        native = [
          "a"
          "b"
          "c"
        ];
      in
      builtins.attrNames top.nixosConfigurations == [
        "a"
        "b"
        "c"
        "host"
        "upstream"
      ]
      && builtins.attrNames vms == native ++ [ "upstream" ]
      && builtins.all (
        name:
        vms.${name}.evaluatedConfig.config.system.build.toplevel.drvPath
        == top.nixosConfigurations.${name}.config.system.build.toplevel.drvPath
      ) (native ++ [ "upstream" ])
      && builtins.all (name: vms.${name}.autostart && !vms.${name}.restartIfChanged) native;

    # microvm.nix reads the `microvm.*` options of a guest of a
    # caisson-microvm configuration from the evaluation result of the guest,
    # and the guest sets them in its modules. The guest `a` sets
    # its hypervisor, CPUs, memory, vsock CID and shares, and its
    # `evaluatedConfig` on the host has exactly those. The guest `b`
    # sets none of them, and its `evaluatedConfig` has the defaults that
    # microvm.nix declares. The runner microvm.nix builds for `a` runs
    # cloud-hypervisor.
    caissonMicrovmGuestsSetTheMicrovmOptionsThemselves =
      let
        vms = microvmHostTop.nixosConfigurations.host.config.microvm.vms;
        a = vms.a.evaluatedConfig.config.microvm;
        b = vms.b.evaluatedConfig;
        defaultOf = name: b.options.microvm.${name}.default;
      in
      a.hypervisor == "cloud-hypervisor"
      && a.vcpu == 2
      && a.mem == 768
      && a.vsock.cid == 3
      &&
        builtins.map (share: { inherit (share) tag proto; }) a.shares == [
          {
            tag = "ro-store";
            proto = "virtiofs";
          }
        ]
      && a.declaredRunner.name == "microvm-cloud-hypervisor-a"
      && b.config.microvm.hypervisor == defaultOf "hypervisor"
      && b.config.microvm.vcpu == defaultOf "vcpu"
      && b.config.microvm.mem == defaultOf "mem"
      && b.config.microvm.vsock.cid == null
      && b.config.microvm.shares == [ ];

    # A microvm configuration declared inside a host is the guest
    # itself: the host's `microvm.vms.upstream` has the evaluation
    # result of the microvm configuration as its `evaluatedConfig`, with
    # the
    # microvm options the module of the guest sets. The host starts it at
    # boot, as microvm.nix does by default, and restarts it when it
    # changes. The microvm configuration records microvm.nix's guest
    # module as one declaration of the source `microvm`.
    microvmConfigurationIsTheGuest =
      let
        top = microvmHostTop;
        vm = top.nixosConfigurations.host.config.microvm.vms.upstream;
        evaluated = vm.evaluatedConfig.config;
        manifest =
          top.caisson.manifest.children.system.x86_64-linux.children.nixos.host.children.system.x86_64-linux.children.microvm.upstream;
      in
      evaluated.system.build.toplevel.drvPath
      == top.nixosConfigurations.upstream.config.system.build.toplevel.drvPath
      && evaluated.microvm.hypervisor == "qemu"
      && evaluated.microvm.mem == 640
      && builtins.map (share: share.proto) evaluated.microvm.shares == [ "9p" ]
      && vm.autostart
      && vm.restartIfChanged
      && manifest.type == "microvm"
      && manifest.outputs.runner.drvPath == evaluated.microvm.declaredRunner.drvPath
      &&
        builtins.map (event: event.origin) (
          builtins.filter (event: event.operation == "declaration" && event.key == "microvm") manifest.history
        ) == [
          {
            project = "microvm";
            file = "nixos-modules/microvm";
          }
        ];

    # The host refuses microvm.nix's `config` and `flake` forms for the
    # name of a guest declared inside it: the assertion for `a` fails
    # when the host sets `microvm.vms.a.flake`, and every assertion
    # holds when it does not. The flake given holds the guest under
    # `nixosConfigurations.a`, as microvm.nix's flake form reads it.
    microvmHostRefusesASecondEvaluation =
      let
        host = microvmHostTop.nixosConfigurations.host;
        refused = host.extendModules {
          modules = [
            {
              microvm.vms.a.flake = {
                outPath = "/var/empty";
                nixosConfigurations.a = host.config.microvm.vms.a.evaluatedConfig;
              };
            }
          ];
        };
        failing = configuration: builtins.filter (check: !check.assertion) configuration.config.assertions;
      in
      failing host == [ ]
      &&
        builtins.map (check: pkgs.lib.hasInfix "`microvm.vms.a.flake`" check.message) (failing refused) == [
          true
        ];

    # A guest that passes `moduleImports` replaces the default selection
    # of the nixos class: `c` selects caisson's `microvm-guest` NixOS
    # module and nothing else, and microvm.nix's guest module is
    # imported through that module. `a` takes the default of the class,
    # caisson's `default` NixOS module among it, and last the
    # `microvm-guest` module the caisson-microvm configuration adds for
    # its nearest NixOS configurations.
    microvmGuestSelectsItsModules =
      let
        pool =
          microvmHostTop.caisson.manifest.children.system.x86_64-linux.children.nixos.host.children.caisson-microvm.pool;
        guest = name: pool.children.system.x86_64-linux.children.nixos.${name};
        reset = (guest "c").moduleImports;
        default = (guest "a").moduleImports;
      in
      reset.act == "reset"
      && reset.selected == [ "modules.nixos.caisson/microvm-guest" ]
      && (guest "c").value.options.microvm ? declaredRunner
      && default.act == "default"
      && builtins.elem "modules.nixos.caisson/default" default.selected
      &&
        pkgs.lib.last default.default == {
          key = "modules.nixos.microvm-guest";
          level = [
            {
              type = "system";
              name = "x86_64-linux";
            }
            {
              type = "nixos";
              name = "host";
            }
            {
              type = "caisson-microvm";
              name = "pool";
            }
          ];
          file = "modules/caisson-microvm/default";
          nearest = true;
        };

    # A guest belongs to the host it is declared inside. In a colmena
    # configuration, a host on a disk layout is a node, and the guests
    # inside it are none: neither a NixOS configuration of its
    # caisson-microvm configuration nor its microvm configuration has
    # colmena's deployment options or the file systems of the layout,
    # which are added to the nearest NixOS configurations declared
    # inside the colmena configuration and the layout, the host. The host still runs both
    # guests.
    microvmGuestsAreNoNodes =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    caisson.caisson-disko.configurations.host = lib.caisson.caisson-disko.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ luksLvmLayout ];
                          caisson.nixos.configurations.host = lib.caisson.nixos.mkConfiguration {
                            extraModuleImports = modules: [ modules."caisson/microvm-host" ];
                            configModule =
                              { lib, ... }:
                              {
                                imports = [ diskoNixosBase ];
                                caisson.caisson-microvm.configurations.pool = lib.caisson.caisson-microvm.mkConfiguration {
                                  configModule =
                                    { lib, ... }:
                                    {
                                      caisson.nixos.configurations.native = lib.caisson.nixos.mkConfiguration {
                                        configModule = microvmGuestBase;
                                      };
                                    };
                                };
                                caisson.microvm.configurations.upstream = lib.caisson.microvm.mkConfiguration {
                                  configModule = upstreamMicrovmGuest;
                                };
                              };
                          };
                        };
                    };
                  };
              };
            };
        };
        published = top.nixosConfigurations;
        guests = [
          "native"
          "upstream"
        ];
      in
      builtins.attrNames top.colmenaHive.nodes == [ "host" ]
      && published.host.options ? deployment
      && published.host.config.fileSystems ? "/boot"
      && builtins.attrNames published.host.config.microvm.vms == guests
      && builtins.all (
        name: !(published.${name}.options ? deployment) && !(published.${name}.config.fileSystems ? "/boot")
      ) guests;

    # The convention for a NixOS configuration inside a layout: the
    # layout declares it under the name of the layout, read from
    # `lib.caisson-core.evalManifest.name`, and caisson's default NixOS
    # module sets the host name to the name the NixOS configuration is
    # declared under. A NixOS configuration that sets a host name itself
    # keeps it.
    diskoNixosConfigurationsNamedAfterTheirLayout =
      let
        layoutWith =
          nixosModule:
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
                          { configModule = nixosModule; };
                    };
                };
              };
          };
        named = layoutWith diskoNixosBase;
        renamed = layoutWith (diskoNixosBase // { networking.hostName = "storage"; });
      in
      builtins.attrNames named.nixosConfigurations == [ "nas-1" ]
      && named.nixosConfigurations.nas-1.config.networking.hostName == "nas-1"
      && renamed.nixosConfigurations.nas-1.config.networking.hostName == "storage";

    # A darwin configuration evaluates for aarch64-darwin whatever the
    # system of the machine that evaluates it, and
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
            probe.baseModule
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

    # A home-manager configuration and a hjem configuration inside a
    # nix-darwin configuration take the home directory and the user ID
    # from the account the nix-darwin configuration declares, and the
    # nix-darwin configuration activates each. Its
    # `postActivation` step runs the activation of the home-manager
    # configuration as the user, as home-manager's nix-darwin module
    # does, and it installs hjem's launchd agent in
    # `/Library/LaunchAgents`, which applies a manifest equal to the
    # manifest hjem's nix-darwin module makes from the same user module. The
    # home-manager configuration is published as `probe@family`.
    darwinActivatesItsHomeManagerAndHjemConfigurations =
      let
        probe = import ../darwin-system { inherit inputs; };
        config = probe.family.config;
        homeManagerManifest =
          probe.familyManifest.children.system.${probe.system}.children.home-manager.probe;
        hjemManifest = probe.familyManifest.children.system.${probe.system}.children.hjem.probe;
        upstream = inputs.nix-darwin.lib.darwinSystem {
          inherit (probe) pkgs;
          modules = [
            { nixpkgs.hostPlatform = probe.system; }
            inputs.hjem.darwinModules.default
            probe.baseModule
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
      homeManagerManifest.value.config.home.homeDirectory == "/Users/probe"
      && homeManagerManifest.value.config.home.uid == 501
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
    # nix-darwin configuration sets it. A nix-darwin configuration whose
    # account for `probe` sets no home directory refuses the
    # home-manager configuration and the hjem configuration of `probe`
    # declared inside it, where the same nix-darwin configuration with
    # the home directory set evaluates. A home-manager configuration or
    # a hjem configuration that sets its home directory itself is
    # refused by an assertion of the nix-darwin configuration or of the
    # hjem configuration, which names the user. An account without `uid` is
    # accepted, as home-manager's nix-darwin module accepts it, and the
    # `home.uid` of the home-manager configuration stays unset.
    darwinRefusesAccountsWithoutAHomeDirectory =
      let
        probe = import ../darwin-system { inherit inputs; };
        hasInfix = probe.pkgs.lib.strings.hasInfix;
        fails = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
        familyWith =
          {
            account,
            homeManagerModule ? probe.homeManagerModule,
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
                        imports = [ (probe.baseModule // { users.users.probe = account; }) ];
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
            inside =
              top.caisson.manifest.children.system.${probe.system}.children.darwin.family.children.system.${probe.system}.children;
          in
          {
            darwinConfig = top.darwinConfigurations.family.config;
            system = top.darwinConfigurations.family.system;
            homeManagerConfig = inside.home-manager.probe.value.config;
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
        withoutHomeDirectory = familyWith { account.uid = 501; };
        setByUser = familyWith {
          account.uid = 501;
          homeManagerModule = {
            imports = [ probe.homeManagerModule ];
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
      && fails withoutHomeDirectory.system.drvPath
      && fails withoutHomeDirectory.hjemManifest
      && refuses "sets no home directory" setByUser.darwinConfig.assertions
      && refuses "sets no home directory" setByUser.hjem.assertions
      && withoutUid.homeManagerConfig.home.homeDirectory == "/Users/probe"
      && withoutUid.homeManagerConfig.home.uid == null
      && withoutUid.hjem.directory == "/Users/probe";

    # A hjem configuration inside a nix-darwin configuration is for a
    # user the nix-darwin configuration declares an account for. The
    # nix-darwin configuration here declares the account `probe` and
    # holds a hjem configuration for `guest`. The
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
                      imports = [ probe.baseModule ];
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

    # A nix-darwin configuration activates the profiles declared inside
    # it in its `postActivation` step: an nvf configuration declared in
    # the nix-darwin configuration as root, and an nvf configuration
    # declared inside the hjem configuration of `probe` as that user,
    # through `launchctl asuser`. The nix-darwin configuration installs
    # the program with which a shell chooses the
    # profile of the system, and the hjem configuration chooses the
    # profile declared inside it for the shells of its user.
    darwinActivatesTheProfilesInsideIt =
      let
        probe = import ../darwin-system { inherit inputs; };
        hasInfix = probe.pkgs.lib.strings.hasInfix;
        nvfConfiguration =
          lib: module:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = dependencies: dependencies.nvf;
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
                    imports = [ probe.baseModule ];
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

    # A hjem configuration that is a caisson top gives what hjem's standalone
    # CLI reads from a file: the version 3 manifest of the user's files,
    # with targets in the user's home directory, and the packages. The
    # manifest of the evaluation result sits under `caisson.manifest`, behind an
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

    # A hjem configuration with no NixOS configuration above it, with an nvf
    # configuration inside it, has in its files what activates the
    # profile when `hjem standalone switch` applies them: the systemd
    # user units `caisson-profiles` on Linux, and the launchd agent
    # `org.caisson.profiles` on macOS, which runs at load, watches the
    # manifest of the current generation, and runs the script the files
    # link at `~/.local/state/caisson/activate-profiles`. A hjem
    # configuration inside a NixOS configuration has neither, since the
    # NixOS configuration activates its profiles.
    hjemStandaloneHasItsProfileActivation =
      let
        linux = import ../hjem-system { inherit inputs; };
        darwin = import ../darwin-system { inherit inputs; };
        targetsOf = manifest: builtins.map (file: file.target) manifest.files;
        withEditor =
          { lib, ... }:
          {
            caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
              ecosystemSrc = dependencies: dependencies.nvf;
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
                caisson.nixos.configurations.probe-nixos = lib.caisson.nixos.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ linux.baseModule ];
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
          .caisson.manifest.children.system.${linux.system}.children.nixos.probe-nixos.children.system.${linux.system}.children.hjem.probe;
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

    # A hjem configuration inside a NixOS configuration takes the home
    # directory of the account the NixOS configuration declares, and its
    # manifest is the manifest the NixOS module of hjem makes from the
    # same user module, the systemd user unit of the user included. The
    # NixOS configuration activates it with the template units hjem's NixOS module writes, which read
    # the manifest file from the directory of this generation, installs
    # the user's packages, and the caisson top publishes it as
    # `hjemConfigurations.probe`.
    hjemInsideNixosIsActivated =
      let
        probe = import ../hjem-system { inherit inputs; };
        inner = probe.inner;
        evaluated = probe.top.nixosConfigurations.probe-nixos;
        services = evaluated.config.systemd.services;
        upstream = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
          inherit (probe) system;
          modules = [
            inputs.hjem.nixosModules.default
            probe.baseModule
            { hjem.users.probe = probe.unitUser; }
          ];
        };
        hjemLib = import "${inputs.hjem}/lib.nix" {
          inherit (probe.pkgs) lib;
          inherit (probe) pkgs;
        };
        upstreamManifest = probe.lib.caisson.hjem.manifestOf hjemLib upstream.config.hjem.users.probe;
        targets = builtins.map (file: file.target) inner.outputs.manifest.files;
        target = evaluated.config.systemd.targets.hjem;
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
        builtins.map (package: package.pname or "") evaluated.config.users.users.probe.packages
      )
      && builtins.attrNames probe.top.hjemConfigurations == [ "probe" ];

    # A NixOS configuration inside a caisson-facter configuration and a
    # NixOS configuration inside a facter configuration, from the report
    # of nixpkgs' facter test, get
    # from nixpkgs' `hardware.facter` module what a NixOS configuration
    # that sets `hardware.facter.reportPath` itself gets: the same
    # report and the same kernel modules for the initrd. The
    # caisson-facter configuration refuses a report of a version it does
    # not know, and a hardware an assertion refuses.
    facterHandsTheReportToNixpkgs =
      let
        reportPath = "${inputs.nixpkgs}/nixos/tests/facter/facter.json";
        nixosModule = {
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
            nixosModule
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
                      configModule = nixosModule;
                    };
                  };
              };
              caisson.facter.configurations.upstream = lib.caisson.facter.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    inherit reportPath;
                    caisson.nixos.configurations.upstream = lib.caisson.nixos.mkConfiguration {
                      configModule = nixosModule;
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

    # A treefmt configuration declared under the name `formatter` is
    # published as `formatter.<system>`, and its wrapper is the
    # derivation the `mkWrapper` of treefmt-nix builds from the same
    # module on the same package set. Its outputs include the
    # configuration file and the check over a source tree. In a
    # composition that knows its root, its check over the root is
    # published as `checks.<system>.treefmt`. A flake may declare
    # treefmt configurations under other names beside `default`.
    treefmtIsTheFormatterTreefmtNixBuilds =
      let
        module = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        };
        declares =
          { lib, ... }:
          {
            caisson.treefmt.configurations.formatter = lib.caisson.treefmt.mkConfiguration {
              ecosystemSrc = dependencies: dependencies.treefmt-nix;
              configModule = module;
            };
            caisson.treefmt.configurations.docs = lib.caisson.treefmt.mkConfiguration {
              ecosystemSrc = dependencies: dependencies.treefmt-nix;
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
            dependencies = { inherit (inputs) nixpkgs treefmt-nix; };
            inherit root;
            projects.caisson = inputs.caisson;
            defaultEcosystemSrc = dependencies: { nixpkgs-lib = dependencies.nixpkgs; };
          }
        );
        rooted = rootedLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = declares;
        };
        children = top.caisson.manifest.children.system.x86_64-linux.children.treefmt;
        evaluation = children.formatter;
        rootedEvaluation = rooted.caisson.manifest.children.system.x86_64-linux.children.treefmt.formatter;
        upstream = inputs.treefmt-nix.lib.mkWrapper pkgs module;
      in
      builtins.attrNames top.formatter == [ "x86_64-linux" ]
      && top.formatter.x86_64-linux.drvPath == upstream.drvPath
      && evaluation.outputs.programs ? nixfmt
      && builtins.isString evaluation.outputs.configFile.drvPath
      && builtins.isString (evaluation.outputs.check ./.).drvPath
      # The check is published in the composition that has a root, as the
      # check of `default` over it, beside the check `registries` that
      # every caisson top carries.
      && builtins.mapAttrs (_: builtins.attrNames) top.checks == { x86_64-linux = [ "registries" ]; }
      && builtins.attrNames rooted.checks == [ "x86_64-linux" ]
      &&
        builtins.attrNames rooted.checks.x86_64-linux == [
          "registries"
          "treefmt"
        ]
      && rooted.checks.x86_64-linux.treefmt.drvPath == (rootedEvaluation.outputs.check root).drvPath
      && rooted.formatter.x86_64-linux.drvPath == upstream.drvPath
      # The configuration `docs` is evaluated.
      && builtins.isString children.docs.outputs.wrapper.drvPath
      # Each configuration records the treefmt-nix it selects.
      &&
        evaluation.ecosystems.treefmt-nix == {
          from = "ecosystemSrc";
          source = "treefmt-nix";
        };

    # An nvf configuration is published as
    # `nvfConfigurations.<system>.<name>`, and its Neovim is the Neovim
    # the `neovimConfiguration` of nvf builds from the same module on the same package set. An nvf configuration
    # declared inside a NixOS configuration or a home-manager configuration is
    # published with the others.
    nvfIsTheNeovimNvfBuilds =
      let
        module = {
          vim.viAlias = true;
          vim.lineNumberMode = "number";
        };
        nvfConfiguration =
          lib:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = dependencies: dependencies.nvf;
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
                    caisson.nvf.configurations.system-editor = nvfConfiguration lib;
                  };
              };
              caisson.home-manager.configurations.alice = lib.caisson.home-manager.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.home-manager;
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
        nixosConfig = top.nixosConfigurations.workstation.config;
        homeManagerConfig = top.homeConfigurations.alice.config;
        unit = nixosConfig.systemd.services.caisson-profile-nvf-system-editor;
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
          "system-editor"
        ]
      # The NixOS configuration activates the profile of the system as root, at boot
      # and at a switch, and lets a shell choose it with `nvim`.
      && unit.wantedBy == [ "multi-user.target" ]
      && !(unit.serviceConfig ? User)
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (
        names nixosConfig.environment.systemPackages
      )
      # The home-manager configuration activates its profile, after its
      # files are linked, and chooses it for its shells.
      && pkgs.lib.hasInfix "/activate" homeManagerConfig.home.activation.caissonProfiles.data
      &&
        homeManagerConfig.home.sessionVariables.CAISSON_NVIM_PROFILE
        == "$HOME/.local/state/caisson/profiles/nvf/home-editor"
      # The profile of `editor`, declared at the caisson top, is a profile of
      # the user, and it points at the Neovim nvf builds.
      && topProfile.scope == "user"
      && topProfile.path == "$HOME/.local/state/caisson/profiles/nvf/editor"
      && topProfile.package.drvPath == upstream.drvPath
      # The configuration records the nvf it selects.
      &&
        top.caisson.manifest.children.system.x86_64-linux.children.nvf.editor.ecosystems.nvf == {
          from = "ecosystemSrc";
          source = "nvf";
        };

    # A nixvim configuration is published as
    # `nixvimConfigurations.<system>.<name>`, and its package is the
    # package the `evalNixvim` of nixvim builds from the same module on the same
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
                ecosystemSrc = dependencies: dependencies.nixvim;
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
        == upstream.config.build.package.drvPath
      # The configuration records the nixvim it selects.
      &&
        top.caisson.manifest.children.system.x86_64-linux.children.nixvim.editor.ecosystems.nixvim == {
          from = "ecosystemSrc";
          source = "nixvim";
        };

    # A nixvim configuration declared inside a NixOS configuration is a
    # profile of the system, as an nvf configuration there is. The NixOS
    # configuration writes the unit that activates the profile as root, at boot and at a
    # switch, and installs the program with which a shell chooses the
    # profile. The unit runs `activate` of the activation package of the
    # profile, and the caisson top publishes the configuration with the others.
    nixvimProfilesInsideANixosConfigurationAreActivated =
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
                    caisson.nixvim.configurations.system-editor = lib.caisson.nixvim.mkConfiguration {
                      ecosystemSrc = dependencies: dependencies.nixvim;
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
        nixosConfig = top.nixosConfigurations.workstation.config;
        unit = nixosConfig.systemd.services.caisson-profile-nixvim-system-editor;
        profile =
          top.caisson.manifest.children.system.x86_64-linux.children.nixos.workstation.children.system.x86_64-linux.children.nixvim.system-editor.outputs;
        names = packages: builtins.map (package: package.name or "") packages;
      in
      builtins.attrNames top.nixvimConfigurations.x86_64-linux == [ "system-editor" ]
      && profile.package.drvPath == upstream.config.build.package.drvPath
      && profile.profile.scope == "system"
      && unit.wantedBy == [ "multi-user.target" ]
      && !(unit.serviceConfig ? User)
      && builtins.elem profile.activationPackage.drvPath (
        builtins.attrNames (builtins.getContext unit.serviceConfig.ExecStart)
      )
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (
        names nixosConfig.environment.systemPackages
      );

    # A topology configuration with NixOS configurations declared inside
    # it reads them as nix-topology reads NixOS configurations evaluated
    # with its NixOS module: the same nodes, and the same rendered
    # diagram. It is published as `topology.<system>` under the name
    # `default`, and its NixOS configurations as `nixosConfigurations`.
    topologyReadsTheNixosConfigurationsDeclaredInside =
      let
        nixosModule = {
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
              caisson.topology.configurations.topology = lib.caisson.topology.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.nix-topology;
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.alpha = lib.caisson.nixos.mkConfiguration {
                      configModule = nixosModule;
                    };
                    caisson.nixos.configurations.beta = lib.caisson.nixos.mkConfiguration {
                      configModule = nixosModule;
                    };
                  };
              };
            };
        };
        upstreamNixosConfiguration =
          hostName:
          import "${inputs.nixpkgs}/nixos/lib/eval-config.nix" {
            system = "x86_64-linux";
            modules = [
              nixosModule
              "${inputs.nix-topology}/nixos/module.nix"
              { networking.hostName = hostName; }
            ];
          };
        upstream = import inputs.nix-topology {
          pkgs = pkgs.extend (import "${inputs.nix-topology}/pkgs/default.nix");
          modules = [
            {
              nixosConfigurations = {
                alpha = upstreamNixosConfiguration "alpha";
                beta = upstreamNixosConfiguration "beta";
              };
            }
          ];
        };
        topology = top.topology.x86_64-linux;
        topologyManifest = top.caisson.manifest.children.system.x86_64-linux.children.topology.topology;
      in
      builtins.attrNames top.nixosConfigurations == [
        "alpha"
        "beta"
      ]
      && builtins.attrNames topology.config.nodes == builtins.attrNames upstream.config.nodes
      && builtins.elem "alpha" (builtins.attrNames topology.config.nodes)
      && topology.config.output.drvPath == upstream.config.output.drvPath
      # The configuration records the nix-topology it selects, and each
      # NixOS configuration inside it the module collection of the
      # composition.
      &&
        topologyManifest.ecosystems.nix-topology == {
          from = "ecosystemSrc";
          source = "nix-topology";
        }
      &&
        topologyManifest.children.system.x86_64-linux.children.nixos.alpha.ecosystems.nixos == {
          from = "defaultEcosystemSrc";
          source = "nixpkgs";
        };

    # A kubenix configuration is published as
    # `kubenixConfigurations.<system>.<name>`, its evaluation result,
    # which is the result the `evalModules` of kubenix gives the same
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
                ecosystemSrc = dependencies: dependencies.kubenix;
                configModule = module;
              };
            };
        };
        upstream = import "${inputs.kubenix}/lib/eval-modules.nix" { inherit pkgs; } { inherit module; };
      in
      top.kubenixConfigurations.x86_64-linux.cluster.config.kubernetes.result.drvPath
      == upstream.config.kubernetes.result.drvPath
      # The configuration records the kubenix it selects.
      &&
        top.caisson.manifest.children.system.x86_64-linux.children.kubenix.cluster.ecosystems.kubenix == {
          from = "ecosystemSrc";
          source = "kubenix";
        };

    # A nixidy configuration is published as
    # `nixidyEnvs.<system>.<name>`, and its rendered environment is the
    # environment the `mkEnv` of nixidy renders from the same module on the same
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
                ecosystemSrc = dependencies: dependencies.nixidy;
                configModule = module;
              };
            };
        };
        upstream = inputs.nixidy.lib.mkEnv {
          inherit pkgs;
          modules = [ module ];
        };
      in
      top.nixidyEnvs.x86_64-linux.prod.environmentPackage.drvPath == upstream.environmentPackage.drvPath
      # The configuration records the nixidy it selects.
      &&
        top.caisson.manifest.children.system.x86_64-linux.children.nixidy.prod.ecosystems.nixidy == {
          from = "ecosystemSrc";
          source = "nixidy";
        };

    # A NixOS configuration activates the profile inside a hjem
    # configuration as the user of that hjem configuration and of no
    # other. The NixOS configuration here holds hjem configurations for
    # `alice` and `bob` and a home-manager configuration for `carol`,
    # each with a profile inside it, and a profile of the system. The
    # configurations inside the NixOS configuration are at the same
    # depth, so a NixOS configuration that matched a profile to the
    # configuration above it by depth would activate each profile for
    # every user. The NixOS configuration writes a unit for the profile
    # of the system, and a unit for the profile of each hjem user, as
    # that user; the home-manager configuration activates its profile
    # itself.
    profilesBelongToTheConfigurationAboveThem =
      let
        probe = import ../hjem-system { inherit inputs; };
        editor =
          lib:
          lib.caisson.nvf.mkConfiguration {
            ecosystemSrc = dependencies: dependencies.nvf;
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
              caisson.nixos.configurations.probe-nixos = lib.caisson.nixos.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    imports = [ probe.baseModule ];
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
                      ecosystemSrc = dependencies: dependencies.home-manager;
                      configModule = {
                        imports = [ (withEditor "carol-editor") ];
                        home.stateVersion = "25.05";
                      };
                    };
                  };
              };
            };
        };
        services = top.nixosConfigurations.probe-nixos.config.systemd.services;
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

    # A system-manager configuration refuses a home-manager configuration that
    # sets `caisson.useUserPackages`, with an assertion that names the
    # home-manager configuration and the user. system-manager throws
    # the failed assertions where `systemConfigs.box` is read, so the
    # check reads whether it throws, and that the same system-manager
    # configuration with the option unset evaluates.
    systemManagerRefusesUseUserPackages =
      let
        topWith =
          useUserPackages:
          hiveLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.system-manager.configurations.box = lib.caisson.system-manager.mkConfiguration {
                  ecosystemSrc = dependencies: dependencies.system-manager;
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
                        ecosystemSrc = dependencies: dependencies.home-manager;
                        configModule = {
                          home.stateVersion = "25.05";
                          caisson.useUserPackages = useUserPackages;
                        };
                      };
                    };
                };
              };
          };
        evaluates =
          useUserPackages: (builtins.tryEval (topWith useUserPackages).systemConfigs.box.drvPath).success;
      in
      evaluates false && !(evaluates true);

    # A system-manager configuration activates the home-manager
    # configuration, the hjem configuration and the nvf configurations
    # declared inside it, as a NixOS configuration does: the
    # home-manager configuration and the hjem configuration take their
    # directory from the account the system-manager configuration
    # declares, the system-manager configuration writes the units that
    # activate them
    # and the profiles, installs the packages of the hjem user, and the
    # home-manager configuration is published as `probe@box`.
    systemManagerActivatesWhatIsDeclaredInside =
      let
        top = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.system-manager.configurations.box = lib.caisson.system-manager.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.system-manager;
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
                      ecosystemSrc = dependencies: dependencies.home-manager;
                      configModule.home.stateVersion = "25.05";
                    };
                    caisson.hjem.configurations.probe = lib.caisson.hjem.mkConfiguration {
                      ecosystemSrc = dependencies: dependencies.hjem;
                      configModule =
                        { lib, pkgs, ... }:
                        {
                          files.".config/probe/greeting".text = "hello";
                          packages = [ pkgs.hello ];
                          caisson.nvf.configurations.hjem-editor = lib.caisson.nvf.mkConfiguration {
                            ecosystemSrc = dependencies: dependencies.nvf;
                            configModule.vim.vimAlias = true;
                          };
                        };
                    };
                    caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
                      ecosystemSrc = dependencies: dependencies.nvf;
                      configModule.vim.viAlias = true;
                    };
                  };
              };
            };
        };
        box = top.systemConfigs.box.config;
        children =
          top.caisson.manifest.children.system.x86_64-linux.children.system-manager.box.children.system.x86_64-linux.children;
        homeManagerConfig = children.home-manager.probe.value.config;
        hjem = children.hjem.probe.value.config;
        names = packages: builtins.map (package: package.name or "") packages;
        systemUnit = box.systemd.services.caisson-profile-nvf-editor;
        hjemUnit = box.systemd.services."hjem-activate@probe";
        hjemProfile =
          children.hjem.probe.children.system.x86_64-linux.children.nvf.hjem-editor.outputs.activationPackage;
      in
      homeManagerConfig.home.homeDirectory == "/home/probe"
      # The system-manager configuration records what it applied, and
      # the home-manager configuration compares against it when
      # activated by hand, as inside a NixOS configuration.
      && box.environment.etc ? "caisson/marker.json"
      && pkgs.lib.hasInfix "/etc/caisson/marker.json" homeManagerConfig.home.activation.caissonDrift.data
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
      # The system-manager configuration activates its profile of the system as root; hjem
      # chooses the profile of the user.
      && systemUnit.wantedBy == [ "multi-user.target" ]
      && !(systemUnit.serviceConfig ? User)
      && builtins.elem "caisson-profile-shims-CAISSON_NVIM_PROFILE" (names box.environment.systemPackages)
      &&
        hjem.environment.sessionVariables.CAISSON_NVIM_PROFILE
        == "/home/probe/.local/state/caisson/profiles/nvf/hjem-editor"
      && builtins.elem pkgs.hello.name (names box.users.users.probe.packages)
      && builtins.attrNames top.homeConfigurations == [ "probe@box" ];

    # A terranix configuration that is a caisson top is its `config.tf.json`
    # file, built from the package set of the composition with the
    # evaluated configuration in its `passthru`, and its modules get the
    # composed library. Declared under a structural caisson top, it is published
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
          ecosystemSrc = dependencies: dependencies.terranix;
          configModule = module;
        };
        published = hiveLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.terranix.configurations.infra = lib.caisson.terranix.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.terranix;
                configModule = module;
              };
            };
        };
      in
      builtins.isString terraform.drvPath
      && terraform.name == "config.tf.json"
      && terraform.passthru.config.terraform.required_version == ">= 1.0"
      && terraform.passthru.config.output.composed.value
      && published.terranixConfigurations.infra.drvPath == terraform.drvPath
      # The configuration records the terranix it selects.
      &&
        published.caisson.manifest.children.system.x86_64-linux.children.terranix.infra.ecosystems.terranix
        == {
          from = "ecosystemSrc";
          source = "terranix";
        };

    # A system-manager configuration that is a caisson top is its system, built
    # for the system it is evaluated for, and its modules get the composed
    # library. It runs on the package set caisson selects, the set named
    # `default`, and its userborn is built on that set. A configuration
    # that sets `nixpkgs.overlays`, which that set leaves without effect,
    # is refused. Declared under a structural caisson top under the name
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
          ecosystemSrc = dependencies: dependencies.system-manager;
          configModule = module;
        };
        withOverlay = hiveLib.caisson.system-manager.mkTopConfiguration {
          ecosystemSrc = dependencies: dependencies.system-manager;
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
                ecosystemSrc = dependencies: dependencies.system-manager;
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
      && published.systemConfigs.default.drvPath == system.drvPath
      # The configuration records the system-manager it selects, and the
      # module collection it reads NixOS modules from.
      &&
        published.caisson.manifest.children.system.x86_64-linux.children.system-manager.default.ecosystems
        == {
          nixpkgs-lib = {
            from = "defaultEcosystemSrc";
            source = "nixpkgs";
          };
          system-manager = {
            from = "ecosystemSrc";
            source = "system-manager";
          };
          nixos = {
            from = "defaultEcosystemSrc";
            source = "nixpkgs";
          };
        };

    # The `WithEcosystemArgs` variants take the evaluator's arguments in
    # `ecosystemArgs`, applied last.
    ecosystemArgsVariantsPassTheirArgumentsToTheEvaluator =
      let
        minimal = (
          hiveLib.caisson.integrations.topValue (
            hiveLib.caisson-core.finalizeTop (
              hiveLib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
                ecosystemSrc = dependencies: dependencies.nixpkgs;
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
              ecosystemSrc = dependencies: dependencies.terranix;
              configModule = {
                config.terraform.required_version = ">= 1.0";
              };
              ecosystemArgs.strip_nulls = false;
            }
          )
        );
        homeManagerConfiguration = hiveLib.caisson.integrations.topValue (
          hiveLib.caisson-core.finalizeTop (
            hiveLib.caisson.home-manager.mkConfigurationWithEcosystemArgs {
              ecosystemSrc = dependencies: dependencies.home-manager;
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
      && builtins.isString homeManagerConfiguration.activationPackage.drvPath;

    # The manifest of each evaluation result records the arguments its
    # configuration handed to the evaluator as it gave them: the names
    # of the attributes of `ecosystemArgs` and of `specialArgs`, and the
    # file and line number where the configuration gave each. This
    # holds for the `WithEcosystemArgs` variant of each integration
    # here, on its real evaluator.
    evaluatorArgsRecordWhatEachVariantGave =
      let
        recordOf =
          configuration:
          builtins.mapAttrs (_: entry: {
            inherit (entry) names;
            inherit (entry.position) file;
            numbered = builtins.isInt entry.position.line;
          }) (hiveLib.caisson-core.finalizeTop configuration).x86_64-linux.evaluatorArgs;
        given = names: {
          inherit names;
          file = "tests/pinned-world/default.nix";
          numbered = true;
        };
      in
      recordOf (
        hiveLib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
          configModule = { };
          ecosystemArgs.prefix = [ "probe-prefix" ];
        }
      ) == {
        ecosystemArgs = given [ "prefix" ];
      }
      &&
        recordOf (
          hiveLib.caisson.terranix.mkConfigurationWithEcosystemArgs {
            ecosystemSrc = dependencies: dependencies.terranix;
            configModule = { };
            ecosystemArgs.strip_nulls = false;
          }
        ) == {
          ecosystemArgs = given [ "strip_nulls" ];
        }
      &&
        recordOf (
          hiveLib.caisson.home-manager.mkConfigurationWithEcosystemArgs {
            ecosystemSrc = dependencies: dependencies.home-manager;
            configModule = { };
            specialArgs.probe = "given";
            ecosystemArgs.check = false;
          }
        ) == {
          specialArgs = given [ "probe" ];
          ecosystemArgs = given [ "check" ];
        };

    registeredModulesReachAdapters =
      let
        registeringLib = core.mkLib (
          declaresPkgs
          // {
            dependencies = { inherit (inputs) nixpkgs-lib nixpkgs; };
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
          ecosystemSrc = dependencies: dependencies.nixpkgs;
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
          dependencies = { inherit (inputs) nixpkgs-lib; };
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
        "dependencies"
        "root"
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

    # A flake declares its platforms on mkLib, and the flake-parts
    # integration reads them from the manifest, so a flake module that
    # names no `systems` still enumerates them.
    systemsDeclaredOnMkLibArePassedToFlakeParts =
      let
        composedWithSystems = core.mkLib {
          dependencies = { inherit (inputs) nixpkgs-lib flake-parts; };
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
            dependencies = { inherit (inputs) nixpkgs-lib nixpkgs; };
            projects = {
              caisson = inputs.caisson;
            };
          }
        );
        system = composedFromProject.caisson.nixos-minimal.mkTopConfiguration {
          ecosystemSrc = dependencies: dependencies.nixpkgs;
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

    # The ecosystem sources a flake declares on mkLib are used by the
    # nixos-minimal adapter with no `ecosystemSrc` passed to its
    # configuration: the
    # package set from `nixpkgs`, the library from `nixpkgs-lib` and
    # the NixOS module collection from `nixos`, each key declared
    # separately, all three pointing at the same nixpkgs pin.
    declaredEcosystemIsUsedByAdapters =
      let
        composedWithDeclaration = core.mkLib (
          declaresPkgs
          // {
            dependencies = {
              pinned-nixpkgs = inputs.nixpkgs;
            };
            defaultEcosystemSrc = dependencies: {
              nixpkgs = dependencies.pinned-nixpkgs;
              nixpkgs-lib = dependencies.pinned-nixpkgs;
              nixos = dependencies.pinned-nixpkgs;
            };
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
        # The manifest of the evaluation result of such a configuration,
        # for its system.
        resultManifest =
          (composedWithDeclaration.caisson-core.finalizeTop (
            composedWithDeclaration.caisson.nixos-minimal.mkConfiguration { configModule = { }; }
          )).x86_64-linux;
        declared = {
          from = "defaultEcosystemSrc";
          source = "pinned-nixpkgs";
        };
      in
      system.config.probePkgs ? hello
      # The evaluation result records the library and the module
      # collection the configuration took from the declaration.
      &&
        resultManifest.ecosystems == {
          nixpkgs-lib = declared;
          nixos = declared;
        };

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

    # The structural integration: a caisson top over the empty class returns
    # the selected registries with the manifest beside them, and the
    # same selectors under flake-parts export the same registries.
    structuralTopMatchesFlakeParts =
      let
        composedWithBoth = core.mkLib {
          dependencies = { inherit (inputs) nixpkgs-lib flake-parts; };
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
        # The same flake, with flake-parts selected by the configuration.
        selecting = composedWithBoth.caisson.flake-parts.mkTopConfiguration {
          ecosystemSrc = dependencies: dependencies.flake-parts;
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
        == [ "caisson/structural" ]
      # The flake records the flake-parts it pins under that name.
      &&
        flake.caisson.manifest.ecosystems.flake-parts == {
          from = "dependencies";
          source = "flake-parts";
        }
      # A flake that selects flake-parts runs on it and records the
      # selection.
      &&
        builtins.attrNames selecting.lib.caisson-core.evalManifest.outputs.exports.libOverlays
        == [ "caisson/structural" ]
      &&
        selecting.caisson.manifest.ecosystems.flake-parts == {
          from = "ecosystemSrc";
          source = "flake-parts";
        };

    # The modules that caisson exports work only inside a configuration
    # that caisson evaluates. caisson publishes none of them in its
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

    # A structural caisson top gathers the checks of the configurations inside
    # it under `checks.<system>` of its outputs and returns them as its
    # `checks`. A check is published under the names of the
    # configurations from the caisson top down to it and its name, joined with
    # `-`, for each system its configuration is evaluated for: the
    # checks of `arm`, which `lab` evaluates for aarch64-linux, are
    # under `checks.aarch64-linux` alone. A check turned off is not
    # gathered.
    checksGatheredUnderJoinedNames =
      let
        names = builtins.mapAttrs (_: builtins.attrNames) checksTop.checks;
        drvPaths = builtins.mapAttrs (_: builtins.mapAttrs (_: check: check.drvPath));
      in
      names == {
        aarch64-linux = [
          "lab-arm-smoke"
          "lab-arm-toplevel"
          "nas-1-boots"
          "nas-1-smoke"
          "nas-1-toplevel"
          "registries"
        ];
        x86_64-linux = [
          "nas-1-boots"
          "nas-1-smoke"
          "nas-1-toplevel"
          "registries"
        ];
      }
      && drvPaths checksTop.checks == drvPaths checksTop.caisson.manifest.outputs.checks
      && checksTop.checks.x86_64-linux.nas-1-smoke.drvPath == (checkMarker "nas-1-smoke").drvPath;

    # A structural configuration declares its checks under `perSystem`,
    # which is evaluated once for each system its children are evaluated
    # for, with `system`, `pkgs` and `pkgSets` among its module
    # arguments. The structural caisson top evaluates its children for both
    # systems of the composition, and the structural configuration `lab`
    # evaluates its children for aarch64-linux. A NixOS configuration
    # has an evaluation result for each system it is evaluated for, and
    # each evaluation result declares the check for its system: `nas-1`
    # for both systems, `arm`, inside `lab`, for aarch64-linux.
    checksDeclaredForEachSystem =
      let
        smoke =
          name:
          { system, pkgSets, ... }:
          {
            caisson.checks.${name} = {
              derivation =
                pkgs.runCommand "${name}-${system}-${builtins.concatStringsSep "," (builtins.attrNames pkgSets)}"
                  { }
                  "touch $out";
              category = "eval";
            };
          };
        top = checksLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              perSystem = smoke "top";
              caisson.structural.configurations.lab = lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.forChildren.systems = [ "aarch64-linux" ];
                    perSystem = smoke "wide";
                    caisson.nixos.configurations.arm = checksNixosConfiguration lib {
                      caisson.checks.smoke = {
                        derivation = checkMarker "arm-smoke";
                        category = "eval";
                      };
                    };
                  };
              };
              caisson.nixos.configurations.nas-1 = checksNixosConfiguration lib (
                { pkgs, ... }:
                {
                  caisson.checks.smoke = {
                    derivation = pkgs.runCommand "nas-1-smoke" { } "touch $out";
                    category = "eval";
                  };
                }
              );
            };
        };
        nas-1 = system: top.caisson.manifest.children.system.${system}.children.nixos.nas-1;
      in
      builtins.mapAttrs (_: builtins.attrNames) top.checks == {
        aarch64-linux = [
          "lab-arm-smoke"
          "lab-arm-toplevel"
          "lab-wide"
          "nas-1-smoke"
          "nas-1-toplevel"
          "registries"
          "top"
        ];
        x86_64-linux = [
          "nas-1-smoke"
          "nas-1-toplevel"
          "registries"
          "top"
        ];
      }
      && top.checks.x86_64-linux.top.name == "top-x86_64-linux-default"
      && top.checks.aarch64-linux.top.name == "top-aarch64-linux-default"
      && top.checks.aarch64-linux.lab-wide.name == "wide-aarch64-linux-default"
      && builtins.attrNames top.caisson.manifest.children.structural.lab.checks == [ "aarch64-linux" ]
      && builtins.attrNames (nas-1 "aarch64-linux").checks == [ "aarch64-linux" ]
      && builtins.attrNames (nas-1 "x86_64-linux").checks == [ "x86_64-linux" ]
      # The structural configuration has no `caisson.checks` outside
      # `perSystem`.
      && !(top.caisson.manifest.value.options.caisson ? checks);

    # The manifest of a configuration records its checks by system and
    # then name, the check turned off included, with the definition
    # that turned it off.
    checksRecordedOnTheManifest =
      let
        recorded =
          checksTop.caisson.manifest.children.system.x86_64-linux.children.nixos.nas-1.checks.x86_64-linux;
      in
      builtins.attrNames recorded == [
        "boots"
        "off"
        "smoke"
        "toplevel"
      ]
      && recorded.off.enable == false
      && recorded.smoke.enable
      && recorded.smoke.category == "eval"
      && recorded.smoke.description == "the NixOS configuration evaluates"
      && builtins.map (position: position.file) recorded.off.code == [ "tests/pinned-world/default.nix" ]
      && builtins.all (position: builtins.isInt position.line) recorded.off.code;

    # The check record of the caisson top is keyed as the gathered checks are.
    # Each entry says where the check is declared, its category, its
    # description, whether its category is volatile and the system
    # features its derivation demands.
    checkRecordOfTheCaissonTop =
      let
        record = checksTop.caisson.manifest.checkRecord;
        boots = record.x86_64-linux.nas-1-boots;
      in
      builtins.mapAttrs (_: builtins.attrNames) record
      == builtins.mapAttrs (_: builtins.attrNames) checksTop.checks
      &&
        builtins.removeAttrs boots [ "code" ] == {
          name = "nas-1-boots";
          system = "x86_64-linux";
          from.namePath = [
            {
              type = "system";
              name = "x86_64-linux";
            }
            {
              type = "nixos";
              name = "nas-1";
            }
          ];
          category = "hardware";
          description = null;
          volatile = true;
          requiredFeatures = [ "kvm" ];
          top = null;
        }
      && builtins.map (position: position.file) boots.code == [ "tests/pinned-world/default.nix" ]
      &&
        record.aarch64-linux.lab-arm-smoke.from.namePath == [
          {
            type = "structural";
            name = "lab";
          }
          {
            type = "system";
            name = "aarch64-linux";
          }
          {
            type = "nixos";
            name = "arm";
          }
        ]
      && record.x86_64-linux.nas-1-smoke.volatile == false
      && record.x86_64-linux.nas-1-smoke.requiredFeatures == [ ];

    # The caisson top records its stages, and the function of a stage selects
    # from the entries of the check record.
    checkStagesRecordedOnTheCaissonTop =
      let
        manifest = checksTop.caisson.manifest;
        stage = manifest.checkStages.quick;
        selected = builtins.mapAttrs (
          _: entries: builtins.attrNames (pkgs.lib.filterAttrs (_: stage.select) entries)
        ) manifest.checkRecord;
      in
      stage.description == "the checks that evaluate"
      && builtins.map (position: position.file) stage.code == [ "tests/pinned-world/default.nix" ]
      &&
        selected == {
          aarch64-linux = [
            "lab-arm-smoke"
            "nas-1-smoke"
            "registries"
          ];
          x86_64-linux = [
            "nas-1-smoke"
            "registries"
          ];
        };

    # The categories caisson declares and those a configuration declares are
    # recorded on the manifests that declare them. A check whose
    # category nothing declares is refused, and so are checks that
    # would be gathered under the same name.
    checksRefusedWhereTheTreeDoesNotHold =
      let
        categories = checksTop.caisson.manifest.checkCategories;
        undeclared = checksTopWith (
          { lib, ... }:
          {
            caisson.nixos.configurations.other = checksNixosConfiguration lib {
              caisson.checks.smoke = {
                derivation = checkMarker "other-smoke";
                category = "undeclared";
              };
            };
          }
        );
        clashing = checksTopWith (
          { lib, ... }:
          {
            caisson.nixos.configurations.nas = checksNixosConfiguration lib {
              caisson.checks."1-smoke" = {
                derivation = checkMarker "nas-1-smoke-again";
                category = "eval";
              };
            };
          }
        );
      in
      builtins.attrNames categories == [
        "build"
        "eval"
        "format"
        "hardware"
        "unit"
        "vm"
      ]
      && categories.hardware.volatile
      && !categories.build.volatile
      && checksFail undeclared.checks
      && checksFail undeclared.caisson.manifest.checkRecord
      && checksFail clashing.checks
      && !checksFail checksTop.checks;

    # A stage declared inside the caisson top is refused.
    checkStagesDeclaredInsideTheCaissonTopAreRefused =
      let
        top = checksLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.nas-1 = checksNixosConfiguration lib {
                caisson.checkStages.inner = {
                  description = "a stage inside the caisson top";
                  select = _: true;
                };
              };
            };
        };
      in
      checksFail top.checks && checksFail top.caisson.manifest.checkRecord;

    # `caisson.exportedChecks` keeps a check out of the `checks` the caisson top
    # returns. The check stays in `outputs.checks` of the manifest and
    # in the check record.
    exportedChecksSelectsThePublishedChecks =
      let
        top = checksTopWith {
          caisson.exportedChecks = builtins.mapAttrs (
            _: checks: builtins.removeAttrs checks [ "nas-1-boots" ]
          );
        };
      in
      !(top.checks.x86_64-linux ? nas-1-boots)
      && top.checks.x86_64-linux ? nas-1-smoke
      && top.caisson.manifest.outputs.checks.x86_64-linux ? nas-1-boots
      && top.caisson.manifest.checkRecord.x86_64-linux ? nas-1-boots;

    # The flake-parts integration publishes the gathered checks as the
    # flake's `checks` output. Under `perSystem`, an entry of `checks`
    # that nothing annotates is a check of the category `build`, an
    # annotated entry carries the position of the entry and of the
    # annotation, and a check declared in `caisson.checks` is defined
    # in `checks` as well. The checks of a NixOS configuration inside
    # the flake are published under its name, and those of a
    # flake-parts configuration inside it under their names alone.
    flakePartsPublishesTheGatheredChecks =
      let
        record = checksFlake.caisson.manifest.checkRecord.x86_64-linux;
        perSystem = checksFlake.lib.caisson-core.evalManifest.value.config.allSystems.x86_64-linux;
      in
      builtins.mapAttrs (_: builtins.attrNames) checksFlake.checks == {
        aarch64-linux = [
          "bare"
          "declared"
          "nas-1-smoke"
          "nas-1-toplevel"
          "plain"
          "registries"
          "suite"
        ];
        x86_64-linux = [
          "bare"
          "declared"
          "nas-1-smoke"
          "nas-1-toplevel"
          "plain"
          "registries"
          "suite"
        ];
      }
      && checksFlake.checks.x86_64-linux.bare.drvPath == (checkMarker "bare").drvPath
      && perSystem.checks ? declared
      && !(perSystem.checks ? hidden)
      && record.bare.category == "build"
      && record.bare.description == null
      && builtins.length record.bare.code == 1
      && record.plain.category == "format"
      && record.plain.description == "the files are formatted"
      && builtins.length record.plain.code == 2
      && record.declared.category == "unit"
      &&
        record.nas-1-smoke.from.namePath == [
          {
            type = "system";
            name = "x86_64-linux";
          }
          {
            type = "nixos";
            name = "nas-1";
          }
        ]
      &&
        record.suite.from.namePath == [
          {
            type = "flake-parts";
            name = "checks";
          }
        ];

    # A flake that declares nothing in `caisson.checks` publishes the
    # entries of `checks` under `perSystem` as flake-parts does, for
    # every system of its `systems`, beside the check `registries` that
    # every caisson top carries.
    flakePartsChecksUnchangedWithoutDeclarations =
      let
        flake = checksLib.caisson.flake-parts.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = {
            perSystem =
              { system, ... }:
              {
                checks = if system == "x86_64-linux" then { only = checkMarker "only"; } else { };
              };
          };
        };
      in
      builtins.mapAttrs (
        _: checks:
        builtins.mapAttrs (_: check: check.drvPath) (builtins.removeAttrs checks [ "registries" ])
      ) flake.checks == {
        aarch64-linux = { };
        x86_64-linux.only = (checkMarker "only").drvPath;
      }
      && builtins.all (checks: checks ? registries) (builtins.attrValues flake.checks);

    # The default checks an integration declares on
    # `mkModuleConfiguration` are recorded on every manifest of the
    # integration, computed from its outputs, with the categories it
    # declares. A configuration annotates a default check with the
    # entry of the same name in `caisson.checks`, or turns it off. The
    # configuration is a caisson top, so it carries `registries` too.
    integrationDefaultChecks =
      let
        plain = stubChecksTopWith { };
        annotated = stubChecksTopWith {
          caisson.checks.artifact.description = "the artifact builds for the probe";
        };
        off = stubChecksTopWith { caisson.checks.artifact.enable = false; };
        redefined = stubChecksTopWith {
          caisson.checks.artifact.derivation = checkMarker "another";
        };
        checksOf = top: top.aarch64-linux.outputs.checks;
        recordOf = checksLib.caisson.integrations.checkRecordOf;
        artifact = (recordOf plain.aarch64-linux).aarch64-linux.artifact;
      in
      builtins.attrNames plain == builtins.sort builtins.lessThan checksSystems
      &&
        (checksOf plain).aarch64-linux.artifact.drvPath == (checkMarker "stub-artifact-aarch64-linux")
        .drvPath
      && artifact.category == "probe"
      && artifact.volatile
      && artifact.description == "the artifact of the configuration builds"
      && builtins.map (position: position.file) artifact.code == [ "tests/pinned-world/default.nix" ]
      &&
        (recordOf annotated.aarch64-linux).aarch64-linux.artifact.description
        == "the artifact builds for the probe"
      && builtins.length (recordOf annotated.aarch64-linux).aarch64-linux.artifact.code == 2
      && builtins.mapAttrs (_: builtins.attrNames) (checksOf off) == { aarch64-linux = [ "registries" ]; }
      && off.aarch64-linux.checks.aarch64-linux.artifact.enable == false
      && checksFail (checksOf redefined);

    # A test declared through the nixos-test integration builds the
    # derivation that `pkgs.testers.runNixOSTest` builds for the same
    # test module, and the manifest of the test records the module of
    # its node as a `declaration` event that names the node. The test
    # is published in no output attribute set.
    nixosTestBuildsWhatRunNixOSTestBuilds =
      let
        manifest = nixosTestTop.caisson.manifest.children.system.x86_64-linux.children.nixos-test.probe;
        nodeEvents = builtins.filter (event: event ? node) manifest.history;
      in
      nixosTestTop.checks.x86_64-linux.probe-test.drvPath == (pkgs.testers.runNixOSTest nixosTestModule)
      .drvPath
      && manifest.outputs.test.drvPath == nixosTestTop.checks.x86_64-linux.probe-test.drvPath
      && manifest.outputs.driver.name == "nixos-test-driver-probe"
      && builtins.isString manifest.outputs.driverInteractive.drvPath
      &&
        builtins.map (event: {
          inherit (event)
            operation
            type
            node
            key
            ;
        }) nodeEvents == [
          {
            operation = "declaration";
            type = "nixos-test";
            node = "machine";
            key = "nodes.machine/0";
          }
        ]
      && builtins.attrNames nixosTestTop.caisson.manifest.exportRecord == [ ];

    # A test declared with no module takes the module registered under
    # its name, `configs/nixosTest/<name>`, and the event of its node
    # names the file that declares the node.
    nixosTestTakesTheModuleRegisteredUnderItsName =
      let
        manifest =
          registeredWorld.caisson.manifest.children.system.x86_64-linux.children.nixos-test.registered;
      in
      builtins.map (event: { inherit (event) key origin; }) (
        builtins.filter (event: event ? node) manifest.history
      ) == [
        {
          key = "nodes.machine/0";
          origin = {
            project = "pinned-world";
            file = "tests/pinned-world/configs/nixosTest/registered";
          };
        }
      ]
      && registeredWorld.checks.x86_64-linux.registered-test.name == "vm-test-run-registered";

    # The default check of a test, `test`, is the run of the test
    # driver, of the category `vm`, and the check record lists the
    # system features the test framework demands of the machine that
    # builds it.
    nixosTestCheckIsAVmCheck =
      let
        entry = nixosTestTop.caisson.manifest.checkRecord.x86_64-linux.probe-test;
      in
      entry.category == "vm"
      && !entry.volatile
      && builtins.elem "kvm" entry.requiredFeatures
      && builtins.elem "nixos-test" entry.requiredFeatures
      &&
        entry.from.namePath == [
          {
            type = "system";
            name = "x86_64-linux";
          }
          {
            type = "nixos-test";
            name = "probe";
          }
        ]
      &&
        builtins.map (position: position.file) entry.code == [
          "lib-overlays/nixos-test/default.nix"
          "tests/pinned-world/default.nix"
        ];

    # A test declared at the top of a flake is evaluated for each
    # system the flake lists, and its check lands under each of them.
    nixosTestAtTheTopOfAFlakeIsEvaluatedForEachSystem =
      builtins.mapAttrs (_: builtins.attrNames) nixosTestFlake.checks == {
        aarch64-linux = [
          "probe-test"
          "registries"
        ];
        x86_64-linux = [
          "probe-test"
          "registries"
        ];
      }
      && nixosTestFlake.caisson.manifest.checkRecord.aarch64-linux.probe-test.system == "aarch64-linux";

    # A test declared inside a NixOS configuration reads the result of
    # the childless evaluation of that NixOS configuration as
    # `nearest.nixos` of its manifest, and its check is published under
    # the name of the NixOS configuration.
    nixosTestInsideANixosConfigurationReadsNearest =
      builtins.mapAttrs (
        _: checks:
        builtins.mapAttrs (_: check: check.name) (
          pkgs.lib.filterAttrs (name: _: pkgs.lib.hasSuffix "-test" name) checks
        )
      ) nixosTestInsideNixos.checks == {
        aarch64-linux.nas-1-smoke-test = "vm-test-run-nas-one";
        x86_64-linux.nas-1-smoke-test = "vm-test-run-nas-one";
      };

    # The nixos integration declares the check `toplevel` for each
    # evaluation result of a NixOS configuration: the NixOS
    # configuration `nas-1`, evaluated for both systems, has
    # `nas-1-toplevel` under both, and `arm`, which `lab` evaluates
    # for aarch64-linux, has `lab-arm-toplevel` under aarch64-linux.
    # The check is the system closure of the evaluation result. Its
    # record says where the nixos integration declares the check and
    # where the caisson top declares `nas-1`.
    nixosConfigurationChecksItsToplevel =
      let
        record = checksTop.caisson.manifest.checkRecord;
        evaluationOf = system: checksTop.caisson.manifest.children.system.${system}.children.nixos.nas-1;
        toplevel = record.x86_64-linux.nas-1-toplevel;
      in
      builtins.all (
        system:
        record.${system}.nas-1-toplevel.category == "build"
        &&
          checksTop.checks.${system}.nas-1-toplevel.drvPath == (evaluationOf system).outputs.toplevel.drvPath
      ) checksSystems
      && checksTop.checks.aarch64-linux ? lab-arm-toplevel
      && !(checksTop.checks.x86_64-linux ? lab-arm-toplevel)
      && toplevel.description == "the system closure of the NixOS configuration builds"
      &&
        builtins.map (position: position.file) toplevel.code == [
          "lib-overlays/nixos/default.nix"
          "tests/pinned-world/default.nix"
        ]
      && builtins.all (position: builtins.isInt position.line) toplevel.code;

    # A NixOS configuration whose system closure fails to build has a
    # `toplevel` check that fails to build: the check is that closure.
    nixosToplevelCheckIsTheBrokenClosure =
      let
        top = checksTopWith (
          { lib, ... }:
          {
            caisson.nixos.configurations.broken = checksNixosConfiguration lib {
              system.systemBuilderCommands = "exit 1";
            };
          }
        );
        evaluation = top.caisson.manifest.children.system.x86_64-linux.children.nixos.broken;
      in
      top.checks.x86_64-linux.broken-toplevel.drvPath == evaluation.outputs.toplevel.drvPath
      && pkgs.lib.hasInfix "exit 1" evaluation.outputs.toplevel.buildCommand;

    # A configuration turns a default check off with
    # `caisson.checks.<name>.enable = false`. The check is not gathered,
    # and the manifest records it with the definition that turned it
    # off after the positions of the default.
    defaultCheckTurnedOff =
      let
        top = checksTopWith (
          { lib, ... }:
          {
            caisson.nixos.configurations.quiet = checksNixosConfiguration lib {
              caisson.checks.toplevel.enable = false;
            };
          }
        );
        recorded =
          top.caisson.manifest.children.system.x86_64-linux.children.nixos.quiet.checks.x86_64-linux.toplevel;
      in
      !(top.checks.x86_64-linux ? quiet-toplevel)
      && top.checks.x86_64-linux ? nas-1-toplevel
      && recorded.enable == false
      &&
        builtins.map (position: position.file) recorded.code == [
          "lib-overlays/nixos/default.nix"
          "tests/pinned-world/default.nix"
          "tests/pinned-world/default.nix"
        ];

    # The home-manager, system-manager, terranix and flake-parts
    # integrations declare their default checks: the activation
    # package of a home-manager configuration as `activation`, the
    # system of a system-manager configuration as `toplevel`, the
    # `config.tf.json` file of a terranix configuration as `json`, and
    # each package of a flake-parts configuration as `<name>-package`.
    # Each check is the output of the evaluation result, of the
    # category `build`. The caisson top carries `registries`.
    integrationsDeclareTheirDefaultChecks =
      let
        checks = defaultChecksTop.checks.x86_64-linux;
        record = defaultChecksTop.caisson.manifest.checkRecord.x86_64-linux;
        children = defaultChecksTop.caisson.manifest.children.system.x86_64-linux.children;
        tools = defaultChecksTop.caisson.manifest.children.flake-parts.tools;
      in
      builtins.attrNames checks == [
        "alice-activation"
        "box-toplevel"
        "hello-package"
        "infra-json"
        "nas-1-toplevel"
        "registries"
      ]
      && checks.alice-activation.drvPath == children.home-manager.alice.outputs.activationPackage.drvPath
      && checks.box-toplevel.drvPath == children.system-manager.box.outputs.toplevel.drvPath
      && checks.infra-json.drvPath == children.terranix.infra.outputs.json.drvPath
      && checks.hello-package.drvPath == tools.outputs.flake.packages.x86_64-linux.hello.drvPath
      && builtins.all (name: record.${name}.category == "build") [
        "alice-activation"
        "box-toplevel"
        "hello-package"
        "infra-json"
      ]
      &&
        record.alice-activation.description
        == "the activation package of the home-manager configuration builds"
      && record.hello-package.description == "the package `hello` of the flake builds"
      &&
        builtins.head (builtins.map (position: position.file) record.box-toplevel.code)
        == "lib-overlays/system-manager/default.nix";

    # The hjem integration declares `manifest`, of the category `eval`:
    # the manifest file of the hjem configuration, whose build runs
    # `cue vet` against the manifest schema of hjem. A hjem
    # configuration that is a caisson top records it with the position
    # of the hjem integration alone, since no configuration declares
    # it.
    hjemConfigurationChecksItsManifest =
      let
        linux = import ../hjem-system { inherit inputs; };
        top = linux.lib.caisson.hjem.mkTopConfiguration {
          configModule = {
            imports = [ linux.user ];
            user = "probe";
            directory = "/home/probe";
          };
        };
        manifest = top.caisson.manifest.checks.${linux.system}.manifest;
      in
      manifest.category == "eval"
      && manifest.derivation.drvPath == top.caisson.manifest.outputs.manifestFile.drvPath
      && builtins.map (position: position.file) manifest.code == [ "lib-overlays/hjem/default.nix" ];

    # The darwin integration declares `toplevel`, the system closure
    # `darwin-rebuild` builds for a nix-darwin configuration.
    darwinConfigurationChecksItsToplevel =
      let
        probe = import ../darwin-system { inherit inputs; };
        top = probe.lib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.darwin.configurations.family = lib.caisson.darwin.mkConfiguration {
                configModule = probe.baseModule;
              };
            };
        };
      in
      top.checks.${probe.system}.family-toplevel.drvPath
      == top.darwinConfigurations.family.config.system.build.toplevel.drvPath
      && top.caisson.manifest.checkRecord.${probe.system}.family-toplevel.category == "build";

    # A caisson top carries the check `registries`, of the category
    # `eval`, for each system. It passes where every registry entry
    # that defines an option under `caisson` imports a module that
    # declares it: the modules caisson registers, and the module
    # `declared`, which imports the core module of caisson.
    registriesPassesWhereEveryEntryImportsItsDeclaration =
      let
        declared = registriesTopWith "declared";
        record = declared.caisson.manifest.checkRecord.x86_64-linux.registries;
      in
      builtins.all (system: checksTop.checks.${system}.registries.message == "") checksSystems
      && declared.checks.x86_64-linux.registries.message == ""
      && record.category == "eval"
      &&
        builtins.map (position: position.file) record.code == [ "lib-overlays/integrations/default.nix" ];

    # The module system gives a module with no file the file of the
    # module that imports it. The registry wraps each entry in such
    # modules, so the wrappers of `plain` carry the file of the
    # configuration module that imports it, which defines an option
    # under `caisson`. The check `registries` reads the files of the
    # entry below the wrappers, and passes.
    registriesIgnoresTheFileThatImportsAnEntry =
      let
        top = registriesLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.nixos.configurations.nas-1 = lib.caisson.nixos.mkConfiguration {
                ecosystemSrc = dependencies: dependencies.nixpkgs;
                configModule =
                  { lib, ... }:
                  {
                    imports = [
                      minimalNixosBase
                      lib.caisson.modules.nixos.plain
                    ];
                    caisson.structural.exportNote = "a note of the configuration module";
                  };
              };
            };
        };
      in
      top.checks.x86_64-linux.registries.message == "";

    # The check `registries` fails to build where a registry entry
    # defines an option under `caisson` and imports no module that
    # declares it, as the module `undeclared` does. Its message names
    # the entry, its file, the configuration that evaluated it, the
    # option, and the file that declares the option.
    registriesRefusesAnEntryWithoutItsDeclaration =
      let
        check = (registriesTopWith "undeclared").checks.x86_64-linux.registries;
        has = infix: pkgs.lib.hasInfix infix check.message;
      in
      has "`modules.nixos.undeclared`, file tests/pinned-world/registries/modules/nixos/undeclared,"
      && has "evaluated in children.system.x86_64-linux.children.nixos.nas-1"
      && has "defines `caisson.structural.exportNote` in tests/pinned-world/registries/modules/nixos/undeclared, declared in modules/nixos/core"
      && builtins.elem "exit 1" (
        builtins.map (arg: pkgs.lib.last (pkgs.lib.splitString "; " arg)) check.args
      );

  };

  failures = builtins.filter (n: results.${n} != true) (builtins.attrNames results);

in
{
  inherit results failures;
  # What the checks that build from the same world read.
  fixtures = {
    inherit
      hiveLib
      nixosConfigurationWithUserPackages
      pkgs
      nixops4ArgPathsOf
      nixops4Entry
      ;
  };
  ok = failures == [ ];
  summary =
    if failures == [ ] then
      "ok: ${toString (builtins.length (builtins.attrNames results))} tests passed"
    else
      throw "pinned-world suite failed: ${builtins.concatStringsSep ", " failures}";
}
