# SPDX-License-Identifier: MIT
#
# The caisson-microvm integration, the native microvm.nix integration:
# it owns the `caisson-microvm` class. A caisson-microvm configuration
# is a set of similarly configured guests that a NixOS host runs as
# microvm.nix virtual machines. It is declared inside the host as
# `caisson.caisson-microvm.configurations.<name>`, and it declares its
# guests as NixOS configurations, under `caisson.nixos.configurations`.
#
# The evaluation is caisson's own `evalModules` over the options the
# guests share, the framework modules, the selection and the
# configuration's module. The shared options are those of microvm.nix
# that every guest has the same: `hypervisor`, `vcpu`, `mem`,
# `interfaces` and `shares`, typed as microvm.nix types them. The
# start options, `autostart`, `restartIfChanged` and `runtimeMaxSec`,
# say how the host starts and stops the guests. `slots.<kind>`
# declares a pool of guests of one kind, `<kind>-1` to `<kind>-<count>`,
# each given the NixOS configuration registered as
# `lib.caisson.configs.nixos.<kind>` and its own vsock CID and shares.
#
# The default module of the class adds caisson's `microvm-guest` NixOS
# module to the nearest NixOS configurations declared inside it, the
# guests. That module imports microvm.nix's guest module and defines
# the guest's microvm options from this configuration. caisson's
# `microvm-host` NixOS module is what a host selects to run the guests:
# it defines microvm.nix's `microvm.vms.<guest>` from them.
#
# A caisson-microvm configuration is not published itself. Its guests
# are published as `nixosConfigurations.<guest>`.
{
  mkLibOverlay,
  ...
}:
{

  imports = [
    # The library of nixpkgs, which this overlay calls through the
    # composed library, imported by key so it is composed wherever
    # this is.
    ((mkLibOverlay ../nixpkgs-lib) // { key = "nixpkgs-lib"; })
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystem = {
        name = "microvm";
        context = "caisson.caisson-microvm";
      };

      # A microvm.nix source: a microvm.nix flake or source tree, either
      # of which holds the guest module at `nixos-modules/microvm` and
      # the host module at `nixos-modules/host`.
      assertMicrovmEcosystemSrc =
        context: ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if
          path != null
          && builtins.pathExists "${path}/nixos-modules/microvm/default.nix"
          && builtins.pathExists "${path}/nixos-modules/host/default.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a microvm.nix flake or source tree (holding nixos-modules/microvm and nixos-modules/host).";

      # The microvm.nix source of a configuration: `explicit` when
      # given, else what the composition declares or pins under the
      # name `microvm`, as recorded on `manifest`.
      ecosystemSrcOf =
        { explicit, manifest }:
        assertMicrovmEcosystemSrc "lib.caisson.caisson-microvm" (resolveEcosystemSrc {
          inherit explicit manifest;
        });

      # Where that microvm.nix source came from, from the same
      # arguments, as a manifest records it under `ecosystems.microvm`.
      ecosystemAccountOf =
        { explicit, manifest }:
        final.caisson.integrations.ecosystemAccountOf ecosystem { inherit explicit manifest; };

      # The guest options microvm.nix declares, from its options module
      # alone, over `lib`. Only the declarations are read, for their
      # types and defaults, so nothing of a NixOS evaluation is needed.
      # The options module also defines options of NixOS, such as
      # `assertions`, which this evaluation does not declare, so the
      # definitions are not checked against the declarations.
      upstreamOptionsOf =
        { lib, src }:
        (lib.evalModules {
          modules = [
            "${src}/nixos-modules/microvm/options.nix"
            { _module.check = false; }
          ];
        }).options.microvm;

      # The options of the class: what the guests share, how the host
      # starts them, and the pools of slots.
      sharedOptions =
        upstream:
        { lib, ... }:
        {
          options = {
            hypervisor = lib.mkOption {
              inherit (upstream.hypervisor) type default;
              description = ''
                The hypervisor every guest of this configuration runs on, as
                microvm.nix's `microvm.hypervisor` takes it. Each guest gets it
                at `mkDefault` priority, so a guest's own definition replaces it.
              '';
            };
            vcpu = lib.mkOption {
              inherit (upstream.vcpu) type default;
              description = ''
                The number of virtual CPUs of every guest, as microvm.nix's
                `microvm.vcpu` takes it. Each guest gets it at `mkDefault`
                priority.
              '';
            };
            mem = lib.mkOption {
              inherit (upstream.mem) type default;
              description = ''
                The memory of every guest in megabytes, as microvm.nix's
                `microvm.mem` takes it. Each guest gets it at `mkDefault`
                priority.
              '';
            };
            interfaces = lib.mkOption {
              inherit (upstream.interfaces) type;
              default = [ ];
              description = ''
                The network interfaces every guest has, as microvm.nix's
                `microvm.interfaces` takes them. Each guest gets these
                definitions beside its own.
              '';
            };
            shares = lib.mkOption {
              inherit (upstream.shares) type;
              default = [ ];
              description = ''
                The directories every guest shares with the host, as
                microvm.nix's `microvm.shares` takes them. Each guest gets
                these definitions beside its own and the shares of its slot.
              '';
            };
            autostart = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether the host starts the guests when it boots. When false,
                a guest runs only after its unit `microvm@<guest>.service` is
                started.
              '';
            };
            restartIfChanged = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether switching the host to a new generation restarts a
                running guest whose configuration changed.
              '';
            };
            runtimeMaxSec = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = ''
                The number of seconds a guest may run before the host stops it.
                Each start of the guest's unit `microvm@<guest>.service` starts
                the timer `microvm-runtime-limit-<guest>.timer`, which counts
                these seconds. When the timer elapses, its service runs
                `systemctl stop microvm@<guest>.service`. The guest's unit
                stays stopped, since systemd does not restart a unit that a stop
                job stopped. When null, a guest runs until it is stopped.
              '';
            };
            slots = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule slotOptions);
              default = { };
              example = lib.literalExpression ''
                {
                  rea = {
                    count = 2;
                    cidBase = 100;
                    shareRoot = "/var/lib/rea";
                    vsockPort = 5000;
                  };
                }
              '';
              description = ''
                Pools of guests of one kind, by kind. A kind with `count` N
                declares the NixOS configurations `<kind>-1` to `<kind>-N`
                inside this configuration. Each of them takes the NixOS
                configuration registered as `lib.caisson.configs.nixos.<kind>`
                as its module, and gets the vsock CID and the shares of its
                slot.

                The configuration records each slot under
                `outputs.slots.<guest>`. When `hypervisor` is
                `cloud-hypervisor`, the slot's `vsockSocket` is the Unix socket
                through which the host reaches the guest's vsock,
                `<stateDir>/<guest>/notify.vsock`, where `<stateDir>` is the
                host's `microvm.stateDir`. A client connects to it, sends
                `CONNECT <port>` and a newline, and reads `OK <n>` and a
                newline before it speaks to the port. On any other hypervisor,
                and inside a host that does not declare `microvm.stateDir`,
                `vsockSocket` is null.
              '';
            };
          };
        };

      # The options of a pool of slots.
      slotOptions =
        { lib, ... }:
        {
          options = {
            count = lib.mkOption {
              type = lib.types.ints.unsigned;
              description = "The number of guests of the kind.";
            };
            cidBase = lib.mkOption {
              type = lib.types.ints.between 2 4294967294;
              description = ''
                The number the vsock CIDs of the guests of the kind count from.
                The guest `<kind>-<k>` gets `cidBase + k` as `microvm.vsock.cid`.
                The CIDs 0, 1 and 2 are reserved, so the base is 2 or more.
              '';
            };
            shareRoot = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "/var/lib/rea";
              description = ''
                The directory on the host under which each guest of the kind has
                a directory of its own. When set, the guest `<kind>-<k>` shares
                `<shareRoot>/<kind>-<k>/in`, read-only, at `/work/in`, and
                `<shareRoot>/<kind>-<k>/out`, writable, at `/work/out`, both
                over virtiofs. When null, the guests of the kind get no shares
                of their slot.
              '';
            };
            vsockPort = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = ''
                The vsock port a guest of the kind serves on, which the programs
                that control the slots read to wait for a started guest. The
                guests do not read it.
              '';
            };
            moduleImports = lib.mkOption {
              type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.raw));
              default = null;
              example = lib.literalExpression ''
                modules: [ modules."caisson/microvm-guest" ]
              '';
              description = ''
                The selection over the nixos class of the registry that each
                guest of the kind is constructed with, as the `moduleImports`
                argument of `lib.caisson.nixos.mkConfiguration` takes it. It
                replaces the default of the class, so a guest of the kind gets
                neither the registry entries named `default` nor what the
                levels above added, and then it lists caisson's `microvm-guest`
                NixOS module itself. When null, each guest gets the default of
                the class.
              '';
            };
            extraModuleImports = lib.mkOption {
              type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.raw));
              default = null;
              description = ''
                A selection over the nixos class of the registry added to the
                selection of each guest of the kind, as the `extraModuleImports`
                argument of `lib.caisson.nixos.mkConfiguration` takes it. When
                null, nothing is added.
              '';
            };
          };
        };

      # The socket through which the host reaches the vsock of the guest
      # `name`, for a configuration on `hypervisor` whose host keeps the
      # working directories of its guests under `stateDir`. The
      # cloud-hypervisor runner of microvm.nix gives a guest that has a
      # vsock CID a hybrid vsock: cloud-hypervisor listens on the Unix
      # socket `notify.vsock` in the guest's working directory
      # `<stateDir>/<guest>`. A client connects to that socket, sends
      # `CONNECT <port>` and a newline, reads `OK <n>` and a newline, and
      # then speaks to the guest's vsock port. A guest on another
      # hypervisor has the kernel's vsock, which needs no socket, and
      # gets null. A host whose configuration does not declare
      # `microvm.stateDir` runs no guests, and its guests get null.
      vsockSocketOf =
        {
          hypervisor,
          stateDir,
          name,
        }:
        if hypervisor == "cloud-hypervisor" && stateDir != null then
          "${stateDir}/${name}/notify.vsock"
        else
          null;

      # The slots of an evaluated caisson-microvm configuration, by the
      # name of the guest: its kind, its number, its vsock CID, the
      # shares of its slot and the port its kind serves on.
      slotsOf =
        slots:
        builtins.listToAttrs (
          builtins.concatMap (
            kind:
            let
              pool = slots.${kind};
            in
            builtins.map (
              index:
              let
                name = "${kind}-${toString index}";
                directory = "${pool.shareRoot}/${name}";
              in
              {
                inherit name;
                value = {
                  inherit kind index;
                  inherit (pool) vsockPort;
                  cid = pool.cidBase + index;
                  shares =
                    if pool.shareRoot == null then
                      [ ]
                    else
                      [
                        {
                          tag = "work-in";
                          source = "${directory}/in";
                          mountPoint = "/work/in";
                          proto = "virtiofs";
                          readOnly = true;
                        }
                        {
                          tag = "work-out";
                          source = "${directory}/out";
                          mountPoint = "/work/out";
                          proto = "virtiofs";
                        }
                      ];
                };
              }
            ) (final.range 1 pool.count)
          ) (builtins.attrNames slots)
        );

      # The NixOS configurations the slots declare: for each slot, a
      # NixOS configuration named after it, with the configuration
      # registered under the name of its kind as its module and the
      # selections of its kind.
      slotsModule =
        { config, lib, ... }:
        {
          caisson.nixos.configurations = builtins.mapAttrs (
            _name: slot:
            let
              pool = config.slots.${slot.kind};
            in
            lib.caisson.nixos.mkConfiguration {
              inherit (pool) moduleImports extraModuleImports;
              configModule =
                lib.caisson.configs.nixos.${slot.kind} or (throw ''
                  lib.caisson.caisson-microvm: the slots of the kind `${slot.kind}` take the
                  NixOS configuration registered as `lib.caisson.configs.nixos.${slot.kind}`,
                  and the composition registers none under that name.
                '');
            }
          ) (slotsOf config.slots);
        };

      # The values of the definitions of an option, as the module
      # system kept them, for a guest to define again in its own
      # evaluation, where the defaults of microvm.nix's submodules are
      # computed against the guest.
      definitionsOf = option: builtins.map (definition: definition.value) option.definitionsWithLocations;

      # The evaluator's call, on the lib of the view being evaluated:
      # the options of the class, the module of the slots, the framework
      # modules of the class, the selection and the configuration's
      # module, with the composition's pinned sources as the `inputs`
      # special argument. `ecosystemArgs`, which only the twin's pattern
      # admits, is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = ecosystemSrcOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          upstream = upstreamOptionsOf { inherit lib src; };
          registry = lib.caisson.modules.caisson-microvm or { };
          frameworkModules = selection.frameworkModules "caisson-microvm" registry;
          moduleImports = selection.moduleImportsOf "caisson-microvm" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-microvm/<name>`), else none.
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "caisson-microvm";
            configModule = args.configModule or null;
          };

          moduleList = [
            (selection.caissonModule {
              key = "caisson.caisson-microvm.sharedOptions";
              file = "caisson-caisson-microvm:sharedOptions";
              module = sharedOptions upstream;
            })
            (selection.caissonModule {
              key = "caisson.caisson-microvm.slots";
              file = "caisson-caisson-microvm:slots";
              module = slotsModule;
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "caisson-microvm";
              specialArgs = {
                inherit lib;
                inputs = manifest.sources;
              }
              // (if (args.pkgSets or null) != null then { inherit (args) pkgSets; } else { })
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          inherit (evaluated) config options;

          # The NixOS host the configuration is declared inside, as its
          # childless evaluation, which leaves out the guests, and the
          # directory under which that host keeps the working directories
          # of its guests. microvm.nix's host module declares
          # `microvm.stateDir`.
          host = selection.nearestOf [ "nixos" ] manifest;
          stateDir = if host == null then null else host.value.config.microvm.stateDir or null;
        in
        {
          value = evaluated;
          # Where microvm.nix came from, as `src` was resolved.
          ecosystems.microvm = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          # What evalModules received: the options of the class, the
          # module of the slots, the framework module of the class, the
          # modules selected from the registry and the configuration's
          # module. microvm.nix's options module gives the types of the
          # shared options; no module list of microvm.nix is evaluated.
          modules = moduleList;
          # What the guests and the host read. `ecosystemSrc` is the
          # microvm.nix source the guests import the guest module from.
          # `guests` is what every guest gets: the hypervisor, the
          # virtual CPUs and the memory, and the definitions of the
          # interfaces and the shares. `start` is how the host starts and
          # stops the guests. `slots` holds the slot of each guest the
          # slots declare, by the name of the guest. The slot of a guest
          # records as `vsockSocket` the Unix socket through which the
          # host reaches the guest's vsock, for the `hypervisor` of this
          # configuration. It is null when that hypervisor is not
          # cloud-hypervisor.
          outputs = {
            ecosystemSrc = src;
            guests = {
              inherit (config) hypervisor vcpu mem;
              interfaces = definitionsOf options.interfaces;
              shares = definitionsOf options.shares;
            };
            start = {
              inherit (config) autostart restartIfChanged runtimeMaxSec;
            };
            slots = builtins.mapAttrs (
              name: slot:
              slot
              // {
                vsockSocket = vsockSocketOf {
                  inherit (config) hypervisor;
                  inherit stateDir name;
                };
              }
            ) (slotsOf config.slots);
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-microvm";
            inherit args;
          };
          type = "caisson-microvm";
          defaultPkgs = args.defaultPkgs or null;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-microvm";
        class = "caisson-microvm";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the NixOS host that declares it under
        # `caisson.caisson-microvm.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The caisson-microvm configuration's module: the options
            # the guests share, the slots, and the guests under
            # `caisson.nixos.configurations`. When absent, the
            # configuration registered under the configuration's name
            # (`lib.caisson.configs.caisson-microvm.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument.
            pkgSets ? null,
            # The package set the guests run on: a function that
            # receives the package sets available to each, by package
            # config name, and returns the set to run on.
            defaultPkgs ? null,
            # The microvm.nix flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-microvm class of the
            # registry. It replaces the default of the class, which is
            # every entry named `default` followed by what the
            # configurations above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            pkgSets ? null,
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        # What the upstream-compatible microvm integration and the
        # host module build on, so all of them read microvm.nix the
        # same way.
        extra = {
          # The microvm.nix source of a configuration: `explicit` when
          # given, else what the composition declares or pins under the
          # name `microvm`, as recorded on `manifest`; refused when it
          # is no microvm.nix source.
          inherit ecosystemSrcOf;
          # Where that microvm.nix source came from, from the same
          # arguments.
          inherit ecosystemAccountOf;
          # The check that a value is a microvm.nix source, with the
          # name of the caller for the message.
          inherit assertMicrovmEcosystemSrc;
          # The Unix socket through which a host reaches the vsock of a
          # guest, from the guest's hypervisor, the host's
          # `microvm.stateDir` and the guest's name, null for a guest
          # that is not on cloud-hypervisor.
          inherit vsockSocketOf;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-microvm = integration.namespace;
      };
    };

}
