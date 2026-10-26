# SPDX-License-Identifier: MIT
#
# The caisson-nixops4 integration, the native NixOps4 integration: it
# owns the `caisson-nixops4` class, prefixed because caisson defines it.
# NixOps4's own class, `nixops4Component`, is the class of the root
# component that NixOps4 evaluates when it deploys. A nixops4
# configuration is a module of the caisson class with `component`, the
# module of that root component: its members, its providers and the
# options its modules declare. It declares the machines NixOps4 deploys
# the way any configuration declares NixOS configurations, under
# `caisson.nixos.configurations.<name>`.
#
# The machines are the NixOS configurations passed up from beneath the
# nixops4 configuration, each under the name it is published under.
# Each becomes a member of the root component under that name: a
# resource of the `exec` type of NixOps4's `local` provider, which copies
# the machine's toplevel to the host over SSH and runs its `bin/apply`.
# The default module of the class adds caisson's `nixops4-apply` NixOS
# module to those configurations, which builds `bin/apply`. The
# component's module sets the SSH settings of a member, and may set
# them from the outputs of other resources. A machine is evaluated once,
# by caisson, before NixOps4 runs, so its NixOS modules cannot read
# the outputs of resources.
#
# NixOps4 evaluates the root component itself, again each time the
# outputs of a resource become known. The integration builds the root
# with `mkRoot` from NixOps4's `nix/lib/lib.nix`, imported over the
# composed library, rather than with the `lib` NixOps4's flake builds
# over its own nixpkgs. When that library needs a package set for a
# deploying system, it gets the set caisson selects for the nixops4
# configuration, for that system.
#
# A nixops4 configuration is published as `nixops4`, the output
# NixOps4's command reads, which holds a single value, so the
# configuration declared under the name `default` fills it. The
# machines are published as well, as the NixOS configurations they
# are, so `nixos-rebuild` and `nixops4 apply` build the same machine.
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
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "nixops4";
        context = "caisson.caisson-nixops4";
      };
      context = "lib.caisson.caisson-nixops4";

      # NixOps4's library, `mkRoot` among it, is the file its flake
      # imports as `lib`. The source must hold it, and the `local`
      # provider whose `exec` type deploys the machines.
      assertNixops4EcosystemSrc =
        ecosystemSrc:
        if
          ecosystemSrc ? modules
          && ecosystemSrc.modules ? nixops4Provider
          && ecosystemSrc.modules.nixops4Provider ? local
          && builtins.pathExists "${ecosystemSrc}/nix/lib/lib.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc.modules.nixops4Provider.local` and `nix/lib/lib.nix` (a NixOps4 flake).";

      # The options of the class: the module of the root component.
      nixops4Options =
        { lib, ... }:
        {
          options.component = lib.mkOption {
            type = lib.types.deferredModule;
            default = { };
            description = ''
              The module of the root component NixOps4 evaluates: its
              members, its providers and the options its modules declare.
              The machines declared beneath the configuration are members
              of it under their names, and this module sets their SSH
              settings.
            '';
          };
        };

      # NixOps4's command addresses a member by its path, the names
      # from the root joined with `.`. A machine whose name contains a
      # `.`, or is empty, could never be addressed, so the root refuses
      # it.
      unaddressable = name: name == "" || final.hasInfix "." name;

      # The machines, by the name each is published under: the NixOS
      # configurations among the entries the nixops4 configuration
      # passes up that belong to it (`integrations.belongsHere`), those
      # with no NixOS configuration between them and the nixops4
      # configuration. A machine beneath a disk layout or a structural
      # group is one. A NixOS configuration declared inside a machine,
      # such as an image, belongs to the machine and is not one. A
      # machine is refused when it has more than one evaluation and when
      # NixOps4 could not address it.
      machinesOf =
        allEntries:
        let
          entries = builtins.filter (
            entry:
            entry.attrset == "nixosConfigurations" && final.caisson.integrations.belongsHere "nixos" entry
          ) allEntries;
          repeated = final.caisson.integrations.evaluatedMoreThanOnce entries;
          published = (final.caisson.integrations.publish entries).nixosConfigurations or { };
          bad = builtins.filter unaddressable (builtins.attrNames published);
        in
        if repeated != [ ] then
          throw ''
            ${context}: a machine is one evaluation of a NixOS configuration,
            and these NixOS configurations are evaluated per system, for more than one system:
            ${builtins.concatStringsSep "\n" (
              builtins.map (
                machine: "  `${machine.name}`, for ${builtins.concatStringsSep ", " machine.systems}"
              ) repeated
            )}
            Declare each machine where a single system is in force.
          ''
        else if bad == [ ] then
          published
        else
          throw ''
            ${context}: NixOps4 cannot address the machines ${
              builtins.concatStringsSep ", " (map (n: "\"${n}\"") bad)
            }. A member name is non-empty and contains no `.`, which separates
            the names of a member path.
          '';

      # The module of the member that deploys `machine`, named `name`:
      # the SSH settings NixOps4's NixOS resource declares, under the
      # same names, and the inputs of the `exec` resource that copies the
      # machine's toplevel to the host and runs its `bin/apply switch`,
      # as NixOps4's NixOS resource does. `bash` is the shell of the
      # deploying system.
      machineModule =
        {
          name,
          machine,
          bash,
        }:
        { config, lib, ... }:
        let
          inherit (lib) mkOption types;
          target = (if config.ssh.user == null then "" else "${config.ssh.user}@") + config.ssh.host;
          # The host key is the only key the SSH client accepts for the
          # host, as NixOps4's NixOS resource has it.
          knownHosts = builtins.toFile "known_hosts" ''
            ${config.ssh.host} ${config.ssh.hostPublicKey}
          '';
        in
        {
          _file = "caisson-caisson-nixops4:machine";
          options = {
            nixos.configuration = mkOption {
              type = types.raw;
              readOnly = true;
              description = ''
                The NixOS configuration this member deploys: the machine
                declared under its name beneath the nixops4 configuration,
                as caisson evaluated it.
              '';
            };
            ssh.user = mkOption {
              type = types.nullOr types.str;
              default = "root";
              description = ''
                The user name of the SSH connection. When `null`, the SSH
                client chooses it from its configuration.
              '';
            };
            ssh.host = mkOption {
              type = types.str;
              default = name;
              defaultText = lib.literalMD "the name of the machine";
              description = "The host the SSH client connects to.";
            };
            ssh.hostPublicKey = mkOption {
              type = types.str;
              description = ''
                The public key of the host. It is the only key the SSH
                client accepts for the host.
              '';
            };
            ssh.opts = mkOption {
              type = types.str;
              default = "";
              description = "Further options of the SSH client, as one shell word.";
            };
            copy.substituteOnDestination = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether the host tries its substituters for the paths it
                receives before they are copied to it.
              '';
            };
            sudo.enable = mkOption {
              type = types.bool;
              default = config.ssh.user != "root";
              defaultText = lib.literalMD ''`false` iff `ssh.user` is `"root"`'';
              description = "Whether the configuration is applied with `sudo`.";
            };
          };
          config = {
            nixos.configuration = machine;
            inputs = {
              executable = bash;
              args = [
                "-c"
                # ConnectTimeout and ConnectionAttempts keep a host that
                # is not up from hanging the deployment. Password and
                # keyboard-interactive authentication are off because
                # stdin is not connected. StrictHostKeyChecking with the
                # configured key alone refuses a host the configuration
                # does not name.
                ''
                  set -euo pipefail
                  export NIX_SSHOPTS="-o ConnectTimeout=10 -o ConnectionAttempts=12 -o KbdInteractiveAuthentication=no -o PasswordAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts} "${lib.escapeShellArg config.ssh.opts}
                  nix copy --to "ssh-ng://$0" "$1" --no-check-sigs --extra-experimental-features nix-command${lib.optionalString config.copy.substituteOnDestination " --substitute-on-destination"}
                  ssh $NIX_SSHOPTS "$0" "${lib.optionalString config.sudo.enable "sudo "}$1/bin/apply switch"
                ''
                target
                machine.config.system.build.toplevel
              ];
            };
          };
        };

      # The package set of a deploying system: the set the selection in
      # force at the nixops4 configuration returns, for that system.
      pkgsFor =
        manifest: system:
        let
          what = "the deployment of the nixops4 configuration `${manifest.name or "default"}` from ${system}";
          pkgSets = final.caisson.integrations.pkgSetsForSystem { inherit context what; } manifest system;
        in
        final.caisson.integrations.pkgSetOf { inherit context what; } manifest pkgSets;

      # The root component: NixOps4's `mkRoot` from its library, imported
      # over the library of the view, with the module that makes a member
      # of each machine and the configuration's `component` module. The
      # root modules receive the composed library and the composition's
      # pinned sources as `inputs`.
      rootOf =
        {
          src,
          lib,
          manifest,
          config,
          specialArgs,
        }:
        let
          nixops4Lib = import "${src}/nix/lib/lib.nix" {
            inherit lib;
            self = src;
            # What NixOps4's library reads from a deploying system: the
            # package set it builds the provider list with.
            selfWithSystem =
              system: f:
              f {
                inherit system;
                pkgs = pkgsFor manifest system;
              };
          };
          machines = machinesOf config.caisson.exports.configurations;
          machinesModule = final.caisson.integrations.caissonModule {
            key = "caisson.caisson-nixops4.machines";
            file = "caisson-caisson-nixops4:machines";
            module =
              {
                lib,
                providers,
                resourceProviderSystem,
                ...
              }:
              {
                _file = "caisson-caisson-nixops4:machines";
                # NixOps4's `local` provider, whose `exec` type deploys
                # the machines. A component module that declares
                # `providers.local` replaces it.
                providers.local = lib.mkDefault src.modules.nixops4Provider.local;
                members = builtins.mapAttrs (name: machine: {
                  type = lib.mkDefault providers.local.exec;
                  imports = [
                    (machineModule {
                      inherit name machine;
                      bash = lib.getExe (pkgsFor manifest resourceProviderSystem).bash;
                    })
                  ];
                }) machines;
              };
          };
        in
        nixops4Lib.mkRoot {
          modules = [
            machinesModule
            config.component
          ];
          specialArgs = specialArgs;
          prefix = [ "nixops4" ];
        };

      # The evaluator's call, on the lib of the view being evaluated:
      # the options of the class, the framework modules of the class, the
      # selection and the configuration's module, with the composition's
      # pinned sources as the `inputs` special argument. `ecosystemArgs`,
      # which only the twin's pattern admits, is merged over the call
      # last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertNixops4EcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          });
          registry = lib.caisson.modules.caisson-nixops4 or { };
          frameworkModules = selection.frameworkModules "caisson-nixops4" registry;
          moduleImports = selection.moduleImportsOf "caisson-nixops4" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-nixops4/<name>`), else none.
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "caisson-nixops4";
            configModule = args.configModule or null;
          };

          moduleList = [
            (selection.caissonModule {
              key = "caisson.caisson-nixops4.nixops4Options";
              file = "caisson-caisson-nixops4:nixops4Options";
              module = nixops4Options;
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          specialArgs = {
            inherit lib;
            inputs = manifest.sources;
          }
          // (if (args.specialArgs or null) != null then args.specialArgs else { });

          evaluated = lib.evalModules (
            {
              class = "caisson-nixops4";
              inherit specialArgs;
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          value = evaluated;
          # Where NixOps4 came from, as `src` was resolved.
          ecosystems.nixops4 = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          # What evalModules received: the options of the class, the
          # framework module of the class, the modules selected from
          # the registry and the configuration's module. Each machine is
          # a separate NixOS configuration, and the history of the
          # machine records the modules NixOS received.
          modules = moduleList;
          outputs.root = rootOf {
            inherit
              src
              lib
              manifest
              specialArgs
              ;
            inherit (evaluated) config;
          };
        };

      # A nixops4 configuration is published as `nixops4`, an output that
      # holds a single value: the root component.
      exportsTo = {
        attrset = "nixops4";
        single = true;
        value = manifest: manifest.outputs.root;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-nixops4";
            inherit args;
          };
          type = "caisson-nixops4";
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-nixops4";
        class = "caisson-nixops4";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.caisson-nixops4.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The nixops4 configuration's module: `component`, and the
            # machines under `caisson.nixos.configurations`. When
            # absent, the configuration registered under the
            # configuration's name
            # (`lib.caisson.configs.caisson-nixops4.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package set the configurations beneath this one run
            # on, and the deployment runs on: a function that receives
            # the package sets available to each, by package config
            # name, and returns the set to run on.
            defaultPkgs ? null,
            # The NixOps4 flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-nixops4 class of the
            # registry. It replaces the default of the class, which is
            # every entry named `default` followed by what the
            # configurations above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies, of the configuration and of the root component.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        extra = {
          # How a nixops4 configuration is published: as `nixops4`.
          inherit exportsTo;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-nixops4 = integration.namespace;
      };
    };

}
