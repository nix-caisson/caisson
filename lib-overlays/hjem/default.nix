# SPDX-License-Identifier: MIT
#
# The hjem integration: it owns the `hjem` class, hjem's class for the
# files and packages of a user. A hjem configuration is the home of a
# user, evaluated per system, once for each system in force where it is declared.
#
# hjem itself evaluates a user only inside its NixOS and nix-darwin
# modules, as a submodule of `hjem.users`; its standalone CLI evaluates
# no modules and reads a manifest. caisson evaluates the user with its
# own `evalModules` over hjem's user module, `modules/common/user.nix`,
# with the arguments hjem's OS modules give it: hjem's library as
# `hjem-lib`, the user's name as `name`, the package set as `pkgs`, and
# the machine above it, if any, as `osConfig`. The user's name is the
# name the configuration is declared under, unless a module of the
# configuration sets `user`.
#
# The outputs are what hjem's tools read: `manifest`, the version 3
# manifest of the user's files as hjem's OS modules write it,
# `manifestFile`, that manifest as a JSON file checked against hjem's
# schema, and `packages`. The configuration is published as
# `hjemConfigurations.<name>` with `manifest` and `packages`, which
# `hjem standalone switch --flake` reads. A failed assertion of the
# user fails every output.
#
# A NixOS configuration activates the hjem configurations declared
# inside it with caisson's `hjem-activation` NixOS module, and gives
# them the home directory of the user's account with the hjem module
# `nixos-parent`.
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
      context = "lib.caisson.hjem.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "hjem";
        context = "caisson.hjem";
      };

      # A hjem source: the hjem flake or source tree, which holds the
      # user module and hjem's library.
      assertHjemSrc =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if
          path != null
          && builtins.pathExists "${path}/modules/common/user.nix"
          && builtins.pathExists "${path}/lib.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a hjem flake or source tree (holding modules/common/user.nix and lib.nix).";

      # The manifest of an evaluated user, as hjem's OS modules write
      # it: version 3, with an entry for every enabled file of the
      # user's file sets.
      manifestOf =
        hjemLib: config:
        let
          fileSets = [
            config.files
            config.xdg.cache.files
            config.xdg.config.files
            config.xdg.data.files
            config.xdg.state.files
          ];
        in
        {
          version = 3;
          files = builtins.concatMap (
            files:
            builtins.map hjemLib.fileToJson (builtins.filter (file: file.enable) (builtins.attrValues files))
          ) fileSets;
        };

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertHjemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the hjem configuration `${name}` at ${system}"
            else
              "this hjem configuration at ${system}";

          pkgSets = selection.pkgSetsAt { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          hjemLib = import "${src}/lib.nix" { inherit lib pkgs; };

          registry = lib.caisson.modules.hjem or { };
          frameworkModules = selection.frameworkModules "hjem" registry;
          moduleImports = selection.moduleImportsOf "hjem" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/hjem/<name>`), else none.
          registered = lib.caisson.configs.hjem or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # The machine the configuration is declared inside, when there
          # is one: the childless evaluation of the nearest NixOS,
          # darwin or system-manager configuration above it, which hjem's
          # modules receive as `osConfig`, null when there is none. A
          # system-manager evaluation is its system, with the
          # configuration and the options in its `passthru`.
          machine = selection.nearestOf [
            "nixos"
            "darwin"
            "system-manager"
          ] manifest;
          osConfig = if machine != null then machine.value.config else null;

          # A user hjem's NixOS module embeds also imports hjem's
          # `modules/nixos/systemd.nix`, which declares the user's
          # systemd units and links them into the user's files, with the
          # `utils` and the options of the machine. A configuration inside
          # a NixOS or system-manager machine that has `utils` gets the
          # same; the minimal NixOS evaluator gives none.
          machineArgs =
            if machine == null then
              { }
            else
              (machine.value._module or { }).args
                or (((machine.value.options or { })._module or { }).args.value or { });
          nixosUser =
            machine != null
            && builtins.elem machine.type [
              "nixos"
              "system-manager"
            ]
            && machineArgs ? utils;

          # What hjem's OS modules set on a user that caisson sets too:
          # the user's name from the name the configuration is declared
          # under, and hjem's default of not clobbering existing files.
          userModule =
            { lib, ... }:
            {
              _file = "caisson-hjem:user";
              user = lib.mkIf (name != null) (lib.mkDefault name);
              clobberFiles = lib.mkDefault false;
            };

          value = lib.evalModules (
            {
              class = "hjem";
              specialArgs = {
                inherit
                  lib
                  pkgs
                  pkgSets
                  osConfig
                  ;
                hjem-lib = hjemLib;
                name = if name != null then name else "hjem";
              }
              # hjem's OS modules hand a user the options of the machine
              # as `osOptions`, and the NixOS module also hands it `utils`.
              // lib.optionalAttrs (machine != null) {
                osOptions = machine.value.options;
              }
              // lib.optionalAttrs nixosUser {
                inherit (machineArgs) utils;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = [
                "${src}/modules/common/user.nix"
                userModule
              ]
              ++ lib.optional nixosUser "${src}/modules/nixos/systemd.nix"
              ++ frameworkModules
              ++ moduleImports registry
              ++ (if configModule == null then [ ] else [ configModule ]);
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          inherit (value) config;

          # Every output fails with the messages of the user's failed
          # assertions, and carries its warnings.
          failed = builtins.map (assertion: assertion.message) (
            builtins.filter (assertion: !assertion.assertion) config.assertions
          );
          checked =
            output:
            if failed != [ ] then
              throw ''
                ${what}:
                ${lib.concatMapStringsSep "\n" (message: "- ${message}") failed}
              ''
            else
              lib.foldr (warning: lib.warn "${what}: ${warning}") output config.warnings;

          manifestValue = checked (manifestOf hjemLib config);
        in
        {
          inherit value;
          outputs = {
            manifest = manifestValue;
            manifestFile = pkgs.writeTextFile {
              name = "manifest-${config.user}.json";
              text = builtins.toJSON manifestValue;
              checkPhase = ''
                set -e
                export CUE_CACHE_DIR=$(pwd)/.cache
                export CUE_CONFIG_DIR=$(pwd)/.config
                ${lib.getExe pkgs.cue} vet -c ${src + "/manifest/v3.cue"} $target
              '';
            };
            packages = checked config.packages;
            # hjem's CLI, which applies a manifest, built from the hjem
            # source the configuration was evaluated with.
            cli = pkgs.callPackage "${src}/cli/package.nix" { };
          };
        };

      # A hjem configuration is published as
      # `hjemConfigurations.<name>`, with `manifest` and `packages`,
      # which is what `hjem standalone switch --flake` reads.
      exportsTo = {
        attrset = "hjemConfigurations";
        value = manifest: {
          inherit (manifest.outputs) manifest packages;
        };
      };

      # What a reader of a file gets from a hjem configuration that is
      # a top: `manifest` and `packages`, which `hjem standalone switch
      # --config` reads, and the manifest of the evaluation under
      # `caisson.manifest`. hjem's CLI serializes the whole value with
      # `nix eval --json`, and an attribute set with `outPath` is
      # serialized as that string, so the live manifest stays out of
      # what the CLI reads.
      projection = manifest: {
        inherit (manifest.outputs) manifest packages;
        caisson = {
          outPath = "caisson manifest: read caisson.manifest";
          inherit manifest;
        };
      };

      # A top evaluated at a single system is the projection of that
      # evaluation; at several, the projections by system.
      top =
        evaluations:
        let
          systems = builtins.attrNames evaluations;
        in
        if builtins.length systems == 1 then
          projection evaluations.${builtins.head systems}
        else
          builtins.mapAttrs (_: projection) evaluations;

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "hjem";
          # A hjem configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # A hjem configuration is activated for its user. Its
          # identity is its manifest file; its marker is a file in the
          # directory of the user, which the hjem module
          # `activation-marker` adds to the files of the configuration.
          # The configurations with an activation declared inside it
          # check the marker.
          activation = {
            identity = manifest: manifest.outputs.manifestFile.outPath;
            marker =
              manifest:
              "${manifest.value.config.directory}/${markerDirectory}/${final.caisson.integrations.markerFileName manifest}";
          };
          evaluate = evaluate args;
        };

      # The directory, relative to the directory of the user, that holds
      # the marker of a hjem configuration.
      markerDirectory = ".local/state/caisson/markers";

      integration = final.caisson.integrations.mkIntegration {
        name = "hjem";
        class = "hjem";
        inherit top;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.hjem.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.hjem.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The hjem flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each at the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the hjem class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
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
            ecosystemSrc ? null,
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        extra = {
          # The manifest of an evaluated user, from hjem's library and
          # the user's `config`.
          inherit manifestOf;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        hjem = integration.namespace;
      };
    };

}
