# SPDX-License-Identifier: MIT
#
# The caisson-facter integration, the native facter integration: it
# owns the `caisson-facter` class. A facter configuration is the
# hardware of a machine: a module of that class with `facter.report`,
# the hardware report nixos-facter writes, as data. It declares the
# NixOS configurations that run on that hardware the way any
# configuration declares NixOS configurations, under
# `caisson.nixos.configurations`.
#
# The evaluation is caisson's own `evalModules` over the report
# options, the assertions, the framework modules, the selection and the
# configuration's module, on the composed library. A project extends
# the class with options of its own about the hardware, beside the
# report. The outputs are the report, checked against the report
# versions the integration knows, the report as the file nixos-facter
# writes, the configuration as data and its hash. Every output fails
# with the messages of the assertions that do not hold.
#
# The default module of the class adds caisson's `caisson-facter-hardware`
# NixOS module to the NixOS configurations declared inside it. That
# module hands the report to nixpkgs' `hardware.facter` module, which
# turns it into the NixOS settings of the hardware: kernel modules,
# firmware, microcode, graphics, networking.
#
# A facter configuration is published under no output attribute set:
# no tool reads a facter configuration from a flake. Its outputs are on
# its manifest.
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
      context = "lib.caisson.caisson-facter";

      # The versions of the report nixos-facter writes that the
      # integration knows. A report of another version is refused, so
      # an unknown report is not handed to nixpkgs' `hardware.facter`.
      supportedReportVersions = [ 1 ];

      # The report options of the class: the report as data, and the
      # file nixos-facter writes, which the report defaults to.
      reportOptions =
        { config, lib, ... }:
        {
          options.facter = {
            reportPath = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                The hardware report nixos-facter writes, `facter.json`.
                `facter.report` defaults to its content.
              '';
            };
            report = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default =
                if config.facter.reportPath == null then
                  { }
                else
                  builtins.fromJSON (builtins.readFile config.facter.reportPath);
              defaultText = lib.literalMD "the content of `facter.reportPath`, or `{ }`";
              description = "The hardware report nixos-facter writes, as data.";
            };
          };
        };

      # The assertions of the class: a module of the class adds one to
      # refuse the hardware, with a message saying why.
      assertionsOptions =
        { lib, ... }:
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  assertion = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the hardware is accepted.";
                  };
                  message = lib.mkOption {
                    type = lib.types.str;
                    description = "Why the hardware is refused, when `assertion` is false.";
                  };
                };
              }
            );
            default = [ ];
            description = ''
              Conditions the hardware must meet. Every output of the facter
              configuration fails with the message of each assertion that is
              false.
            '';
          };
        };

      # A value as data: attributes whose names begin with `_`, and
      # functions, left out.
      stripInternal =
        value:
        if builtins.isAttrs value then
          final.concatMapAttrs (
            name: inner:
            if final.hasPrefix "_" name || builtins.isFunction inner then
              { }
            else
              { ${name} = stripInternal inner; }
          ) value
        else if builtins.isList value then
          builtins.map stripInternal (builtins.filter (inner: !builtins.isFunction inner) value)
        else
          value;

      # The outputs of an evaluated facter configuration, from its
      # `config`.
      hardwareOf =
        config:
        let
          inherit (config.facter) report;
          failed =
            builtins.map (assertion: assertion.message) (
              builtins.filter (assertion: !assertion.assertion) config.assertions
            )
            ++ (
              if report == { } || builtins.elem (report.version or null) supportedReportVersions then
                [ ]
              else
                [
                  "the facter report has version ${
                    builtins.toJSON (report.version or null)
                  }, and the versions caisson knows are ${builtins.toJSON supportedReportVersions}"
                ]
            );
          checked =
            value:
            if failed == [ ] then
              value
            else
              throw ''
                ${context}: the hardware is refused:
                ${builtins.concatStringsSep "\n" (builtins.map (message: "- ${message}") failed)}
              '';
          serializableConfig = checked (stripInternal (builtins.removeAttrs config [ "caisson" ]));
        in
        {
          report = checked report;
          # The report as the file nixos-facter writes.
          reportFile = builtins.toFile "facter.json" (builtins.toJSON (checked report));
          # The configuration as data: the report and what the modules of
          # the class declare about the hardware, without caisson's
          # options.
          inherit serializableConfig;
          # The identity of the hardware: the hash of the configuration
          # as data.
          hash = builtins.hashString "sha256" (builtins.toJSON serializableConfig);
        };

      # The evaluator's call, on the lib of the view being evaluated.
      # `ecosystemArgs`, which only the twin's pattern admits, is merged
      # over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          registry = lib.caisson.modules.caisson-facter or { };
          frameworkModules = selection.frameworkModules "caisson-facter" registry;
          moduleImports = selection.moduleImportsOf "caisson-facter" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-facter/<name>`), else none.
          name = manifest.name or null;
          registered = lib.caisson.configs.caisson-facter or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          moduleList = [
            reportOptions
            assertionsOptions
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "caisson-facter";
              specialArgs = {
                inherit lib;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          value = evaluated;
          # What evalModules received: the report options and the
          # assertions, the framework module of the class, the modules
          # selected from the registry and the configuration's
          # module. The report is data, read from `facter.reportPath`.
          modules = moduleList;
          outputs = hardwareOf evaluated.config;
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-facter";
            inherit args;
          };
          type = "caisson-facter";
          defaultPkgs = args.defaultPkgs or null;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-facter";
        class = "caisson-facter";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.caisson-facter.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The facter configuration's module: `facter.report` or
            # `facter.reportPath`, and the NixOS configurations that run
            # on the hardware under `caisson.nixos.configurations`. When
            # absent, the configuration registered under the
            # configuration's name (`lib.caisson.configs.caisson-facter.<name>`),
            # if any. Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package set the configurations beneath this one run
            # on: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on.
            defaultPkgs ? null,
            # The selection over the caisson-facter class of the
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
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        extra = {
          # The versions of the report nixos-facter writes that the
          # integration accepts.
          inherit supportedReportVersions;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-facter = integration.namespace;
      };
    };

}
