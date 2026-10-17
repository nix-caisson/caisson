# SPDX-License-Identifier: MIT
#
# What an integration is written from: the functions every integration
# overlay shares, under `lib.caisson.integrations`. Each integration
# imports this overlay by key, so composing any of them composes
# this, and reads the functions through `final`. `mkIntegration` and
# `mkAltIntegration` generate an integration from its declaration
# (design section 8) out of these pieces.
#
#   mkEvaluation         the evaluation an entry point performs: every
#                        integration takes exactly the caisson-shaped
#                        arguments (configModule, moduleImports,
#                        specialArgs, pkgSets, ecosystemSrc, and the
#                        few of its target) and composes the evaluator's
#                        call from them. Nothing else is forwarded: an
#                        evaluator argument handed in directly would be
#                        silently overwritten, silently dropped, or
#                        surface as a conflict deep inside the
#                        evaluator. The `...WithEcosystemArgs` twin of
#                        each entry point is the way to the evaluator's
#                        full surface: the same arguments plus
#                        `ecosystemArgs`, merged over the composed call
#                        verbatim, last.
#
#                        The signature is the pattern of the entry
#                        point. An entry point is a function of an
#                        attribute set pattern with no `...`, so Nix
#                        matches the call against the pattern before any
#                        of the body exists: a missing or unexpected
#                        argument is Nix's error, named after the
#                        entry point and raised at the call site, with
#                        no frame of the composition or the evaluator
#                        above it. The pattern names every argument the
#                        entry point takes and marks the optional arguments
#                        with `? null`; the composition supplies the
#                        value of an omitted argument, so the pattern
#                        binds `@args` and hands the call on as it came.
#                        `builtins.functionArgs` reads the signature
#                        back as data.
#   resolveEcosystemSrc  the layered ecosystem-source resolution:
#                        caisson-core's `resolve` (the explicit
#                        argument, then the composition's declared
#                        `defaultEcosystemSrc.<name>`, then the pinned
#                        source with exactly the declared name), with
#                        the miss interpreted here, where the
#                        integration knows what to say; the resolver
#                        itself never formats a message, because a miss
#                        is the plain value null. The declarations and
#                        sources are read from the composition's
#                        manifest; a manifest-less
#                        composition resolves only the explicit
#                        argument.
#   coreModules          the selections every integration draws
#   defaultModuleImports from the registry of its class, by entry name:
#                        every entry named `core` (the local `core` and
#                        a consumed project's `<project>/core`) is the
#                        framework module of the class, forced into
#                        every evaluation before anything the
#                        evaluation selects; every entry named
#                        `default`, likewise, is the default default,
#                        what `moduleImports` selects when the
#                        evaluation names nothing. Any project a
#                        composition lists may register either, for any
#                        class: a `core` is the big hammer, for a module
#                        the class cannot function without; a `default`
#                        is what the project gives every configuration
#                        of the class unless it selects otherwise.
#   frameworkModules     the framework module of a class, forced into
#                        every evaluation of it: the core of caisson
#                        itself for the class, which declares the
#                        manifest, the configurations declared beneath
#                        and `caisson.exports`, followed by
#                        `coreModules` of the registry.
#   mkModuleConfiguration
#                        a configuration that is a module evaluation,
#                        from the evaluator step of an integration.
#                        It holds configurations of any integration
#                        beneath it: the configurations its modules
#                        declare are its children, and what they
#                        export is passed up through it.
{ closure-lib, mkLibOverlay, ... }:
{

  # These functions use `builtins` and the list, attribute set, string
  # and function helpers of caisson-core (`caisson-core.lists` and its
  # neighbours), so this overlay composes in a library that holds no
  # library of nixpkgs. An integration that evaluates modules imports
  # that library itself. The one import is the names of the framework
  # under `lib.caisson`, so a library that holds an integration holds
  # those names.
  imports = [ ((mkLibOverlay ../framework) // { key = "framework"; }) ];

  overlay =
    final: prev:
    let

      inherit (final.caisson-core.lists)
        unique
        zipListsWith
        init
        last
        ;
      inherit (final.caisson-core.attrsets) genAttrs filterAttrs;
      inherit (final.caisson-core.strings) hasInfix;
      inherit (final.caisson-core.functions) functionArgs setFunctionArgs;

      resolveEcosystemSrc =
        {
          # the integration's name for its ecosystem, e.g. "nixpkgs"
          name,
          # names the caller in the miss message, e.g. "caisson.nixos"
          context,
        }:
        {
          explicit ? null,
          manifest ? final.caisson-core.libManifest or { },
        }:
        let
          resolved = final.caisson-core.resolve {
            inherit name explicit;
            defaults = manifest.defaultEcosystemSrc or { };
            sources = manifest.sources or { };
          };
        in
        if resolved != null then
          resolved
        else
          throw ''
            ${context}: no ${name} ecosystem source. Pass `ecosystemSrc`
            explicitly, declare `defaultEcosystemSrc.${name}` in the mkLib call,
            or pin a source named `${name}` in the `sources` passed to mkLib.
          '';

      named =
        leaf: name:
        let
          n = builtins.stringLength name;
          l = builtins.stringLength leaf;
        in
        name == leaf || (n > l && builtins.substring (n - l - 1) (l + 1) name == "/${leaf}");

      select =
        leaf: registry:
        builtins.map (name: registry.${name}) (builtins.filter (named leaf) (builtins.attrNames registry));

      # The framework module of `class`, over the registry of the
      # class in the composition an evaluation runs in. The core of
      # caisson itself is read from the closure, so it is there
      # however the integration was registered.
      frameworkModules =
        class: registry: [ closure-lib.caisson.modules.${class}.core ] ++ select "core" registry;

      # The selection of an evaluation over the registry of its class,
      # from the arguments of the configuration, as a function of that
      # registry: what `moduleImports` selects, and with none
      # given the default of the class, every entry named `default`
      # followed by what the levels above the evaluation added for the
      # class (`caisson.forChildren.extraDefaultModuleImports`), each
      # applied to the lib of the evaluation.
      #
      # `extraModuleImports` of the configuration is appended to
      # either: it adds to the selection where `moduleImports`
      # replaces it, so a configuration that adds a module keeps the
      # default of its class.
      moduleImportsOf =
        class:
        { lib, manifest }:
        args: registry:
        let
          given = args.moduleImports or null;
          extra = args.extraModuleImports or null;
        in
        (
          if given != null then
            given registry
          else
            select "default" registry
            ++ builtins.concatMap (selection: selection lib) (manifest.defaultModuleImports.${class} or [ ])
        )
        ++ (if extra == null then [ ] else extra registry);

      # The package sets available to an evaluation, by package config
      # name: the package configs its manifest holds, each projected to
      # its set at `system`. `context` names the entry point and `what`
      # the configuration, for the message of a config that builds no
      # set at that system.
      pkgSetsAt =
        { context, what }:
        manifest: system:
        builtins.mapAttrs (
          name: config:
          (config.children.nixpkgs.${system} or (throw ''
            ${context}: the package config `${name}` builds no set for ${system},
            which ${what} needs. Add the system to `caisson.nixpkgs.systems`
            in the config's module.
          '')
          ).value
        ) (manifest.pkgSets or { });

      # The package set a configuration runs on: the selection in
      # force at its manifest, applied to the package sets available
      # to it. A selection is a function that receives those sets, as
      # an attribute set by package config name, and returns the set to
      # run on. The `defaultPkgs` argument of a constructor makes one for
      # that configuration and everything beneath it
      # (`mkModuleConfiguration` records it), and a configuration that
      # passes none runs on what the nearest configuration above it
      # selected. Where no configuration from the top down to this one
      # selected, it runs on the set named `default`. Every integration
      # whose configurations run on a package set selects it here.
      pkgSetOf =
        { context, what }:
        manifest: pkgSets:
        if (manifest.defaultPkgs or null) != null then
          manifest.defaultPkgs pkgSets
        else
          pkgSets.default or (throw ''
            ${context}: ${what} runs on the package set named `default`,
            since no configuration from the top down to it selects one, and the
            package sets available here are ${
              if pkgSets == { } then "none" else builtins.concatStringsSep ", " (builtins.attrNames pkgSets)
            }. Declare a package config named `default` with `pkgSets` on mkLib,
            or select a set where a configuration is constructed
            (`defaultPkgs = pkgSets: pkgSets.<name>;`).
          '');

      # A configuration that is a module evaluation. `type` is the
      # name of the integration and `perSystem` whether it evaluates a
      # configuration per system, as caisson-core.mkConfiguration
      # takes them. `evaluate` is the evaluator step of the
      # integration: it takes the view being evaluated, `{ lib,
      # manifest }`, and returns `value`, the evaluation as the
      # evaluator returned it, `outputs`, the references into it that
      # the integration declares, and `config` where the evaluated
      # options are not `value.config`. Its module list carries
      # `frameworkModules` of its class.
      #
      # The configurations its modules declare under
      # `caisson.<integration>.configurations`, of any integration,
      # are its children, and `caisson.exports`, which carries what
      # they pass up, is its `exports` output.
      #
      # `defaultPkgs` is the selection of a package set the configuration
      # was constructed with, null when it was given none. It is
      # recorded on the manifest, where it is in force for the
      # configuration and everything beneath it.
      #
      # `exportsTo` says how the configuration is published: `attrset`,
      # the output attribute set (`nixosConfigurations`), and `value`,
      # the function from the manifest of the configuration to what is
      # published. It may carry `name`, for an integration whose
      # configurations are known by a name other than the one they are
      # declared under: a function of `{ name, manifest }`, the name
      # the configuration is passed up under and its manifest,
      # returning `value`, the name to publish it under, and
      # optionally `description`, a sentence saying what it did. It may
      # carry `single`, for an output that holds the one configuration
      # named `default`, and `bySystem`, for an output keyed by the
      # system of each evaluation first (`packages.<system>.<name>`). It is
      # recorded on the manifest, and applied where the configuration
      # is passed up (`entriesOf`). Null for a configuration that is
      # not published under a name.
      #
      # `activation` is given by an integration whose configurations
      # are activated on a machine or for a user: NixOS, darwin and
      # system-manager machines, homes, hjem configurations. It holds
      # two functions of a manifest of the configuration. `identity`
      # returns the store path that names what the activation applies,
      # computed from the childless evaluation, or null where there is
      # none. `standsAlone`, when true, says the configuration is
      # applied on its own, as a machine is on its own host, so that it
      # checks no configuration above it. `marker` returns the path of the file the activation
      # writes that identity into, as shell text, which may name
      # variables such as `$HOME`. It is recorded on the manifest. A
      # configuration with an activation declared beneath one checks
      # the marker of the nearest such configuration above it when it
      # is activated (`driftCheckOf`). Null for a configuration that is
      # not activated.
      mkModuleConfiguration =
        {
          type,
          perSystem ? false,
          defaultPkgs ? null,
          exportsTo ? null,
          activation ? null,
          evaluate,
        }:
        final.caisson-core.mkConfiguration {
          inherit type perSystem;
          record =
            (if defaultPkgs == null then { } else { inherit defaultPkgs; })
            // (if exportsTo == null then { } else { inherit exportsTo; })
            // (if activation == null then { } else { inherit activation; });
          evaluate =
            view:
            let
              evaluated = evaluate view;
              config = evaluated.config or evaluated.value.config;
              options = evaluated.options or evaluated.value.options;
            in
            {
              inherit (evaluated) value;
              outputs = (evaluated.outputs or { }) // {
                exports = config.caisson.exports;
              };
              children = view.lib.caisson.integrations.childrenOf { inherit options config; };
              # What the modules give the configurations beneath
              # (`caisson.forChildren`).
              forChildren = {
                extraDefaultModuleImports = builtins.mapAttrs (_: selection: [
                  selection
                ]) config.caisson.forChildren.extraDefaultModuleImports;
                defaultPkgs = config.caisson.forChildren.defaultPkgs;
                systems = config.caisson.forChildren.systems;
              };
            };
        };

      # The body of both entry points, from the caisson arguments a
      # pattern admitted: `compose` takes them and returns an attrset
      # holding `ecosystemArgs`, the evaluator's call as composed,
      # beside whatever `evaluate` needs; `evaluate` takes that attrset
      # and the call to make. `ecosystemArgs`, which only the twin's
      # pattern admits, is merged over the composed call verbatim,
      # last.
      mkEvaluation =
        { compose, evaluate }:
        args:
        let
          composed = compose args;
        in
        evaluate composed (composed.ecosystemArgs // (args.ecosystemArgs or { }));

      # The `mkTopConfiguration` of an integration: it takes the
      # arguments of `mkConfiguration`, finalizes the configuration
      # with no parent, and applies `top` to the manifest. It has the
      # argument pattern of `mkConfiguration`, so a reader of
      # `builtins.functionArgs` sees the same arguments.
      topConfiguration =
        top: mkConfiguration:
        setFunctionArgs (args: top (final.caisson-core.finalizeTop (mkConfiguration args))) (
          functionArgs mkConfiguration
        );

      # An integration that owns a module class, declared. The
      # declaration carries the entry points as pattern functions,
      # `mkConfiguration` and its `WithEcosystemArgs` twin, and the
      # result holds `namespace`, the value of `lib.caisson.<name>`: the
      # entry points, the registration form `mkModule` bound to the
      # class, `configurationsModule`, and whatever `extra` adds beside
      # them (variants, and the composition an alt over the class
      # reads). The overlay file writes the namespace under its key,
      # since the output attribute names of an overlay must not depend
      # on `final`:
      #
      #   overlay = final: prev:
      #     let integration = final.caisson.integrations.mkIntegration { ... }; in
      #     { caisson = (prev.caisson or { }) // { nixos = integration.namespace; }; };
      mkIntegration =
        {
          name,
          class,
          mkConfiguration,
          mkConfigurationWithEcosystemArgs,
          # What a configuration of this integration that has no parent
          # returns, as a function of its finalized manifest. When
          # given, the integration has a `mkTopConfiguration`: it takes
          # the arguments of `mkConfiguration`, finalizes the
          # configuration with no parent, and applies this function to
          # the manifest. An integration whose configurations are only
          # declared inside other configurations gives none.
          top ? null,
          extra ? { },
        }:
        let
          mkModule = final.caisson-core.mkModule class;

          mkTopConfiguration = topConfiguration top mkConfiguration;

          # A configuration for every configuration registered in the
          # class (`configs/<class>/<name>`), by its name, each as
          # `mkConfiguration` builds it without `configModule`. The
          # arguments apply to all of them; a tree that wants only some,
          # or a configuration that differs, declares them with
          # `mkConfiguration`.
          # It exists for an integration whose `mkConfiguration` takes
          # `configModule` as optional, which is the mark that it finds
          # the module registered under the configuration's name.
          findsModuleByName = (functionArgs mkConfiguration).configModule or false;
          mkConfigurations = setFunctionArgs (
            args:
            if args ? configModule then
              throw ''
                lib.caisson.${name}.mkConfigurations gives every configuration the
                module registered under its name; pass `configModule` to
                lib.caisson.${name}.mkConfiguration for a configuration that takes
                another.
              ''
            else
              builtins.mapAttrs (_: _: mkConfiguration args) (final.caisson.configs.${class} or { })
          ) (builtins.removeAttrs (functionArgs mkConfiguration) [ "configModule" ]);
        in
        {
          namespace = {
            inherit
              mkConfiguration
              mkConfigurationWithEcosystemArgs
              mkModule
              ;
            configurationsModule = configurationsModuleOf name;
          }
          // (if findsModuleByName then { inherit mkConfigurations; } else { })
          // (if top == null then { } else { inherit mkTopConfiguration; })
          // extra;
        };

      # The module of the integration `name` that lets a configuration
      # hold configurations of that integration beneath it. It declares
      # `caisson.<name>.configurations`, which takes what
      # `lib.caisson.<name>.mkConfiguration` returns and holds the
      # finished manifest, and `caisson.<name>.exported`, which selects
      # those that are passed up. A configuration learns its name and
      # its parent from where it is declared, so the option finalizes
      # each entry when it is read, with the attribute it is declared
      # under and the childless manifest of the evaluation. caisson's
      # core module imports this module for each integration of
      # caisson. An integration written outside caisson registers a
      # module that imports it where its configurations may be declared.
      configurationsModuleOf = name: configurationsModuleFor [ name ];

      # The module that declares the options `configurationsModuleOf`
      # declares, for several integrations at once. The core module of
      # caisson imports it once, for all the integrations of caisson.
      # The types of the options are built once for all of them.
      configurationsModuleFor = names: {
        key = "caisson-configurations:${builtins.concatStringsSep "," names}";
        imports = [
          (
            { lib, options, ... }:
            let
              types = configurationsTypesOf lib;
            in
            {
              options.caisson = genAttrs names (
                name: configurationsOptionsOf { inherit lib options types; } name
              );
            }
          )
        ];
      };

      # The types of `caisson.<name>.configurations` and
      # `caisson.<name>.exported`, the same for every integration.
      configurationsTypesOf = lib: {
        configurations = lib.types.lazyAttrsOf lib.types.raw;
        exported = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
      };

      # The options `caisson.<name>.configurations` and
      # `caisson.<name>.exported` of the integration `name`, in the
      # evaluation whose `lib` and `options` are given, with `types` from
      # `configurationsTypesOf`.
      configurationsOptionsOf =
        {
          lib,
          options,
          types ? configurationsTypesOf lib,
        }:
        name:
        let
          manifest = lib.caisson-core.evalManifest;
          what = childName: "`caisson.${name}.configurations.${childName}`";
          finalize =
            childName: child:
            let
              finalized = lib.caisson-core.finalizeChild {
                name = childName;
                what = what childName;
                parent = manifest.childlessManifest;
              } child;
              # The integration of what was declared: of the
              # manifest, or of the evaluations of a configuration
              # evaluated per system, null where it has none.
              declaredType =
                if isManifest finalized then
                  finalized.type
                else if finalized == { } then
                  null
                else
                  (builtins.head (builtins.attrValues finalized)).type;
            in
            if manifest == null then
              throw ''
                ${what childName} is declared in an evaluation that carries no manifest
                (`lib.caisson-core.evalManifest` is null there), so no
                configuration can be finalized beneath it.
              ''
            else if manifest.childless then
              throw ''
                The result of the ${name} configuration `${childName}` is not
                readable from the ${manifest.type} configuration it is declared in, or
                from another configuration beneath that configuration; only the
                options of the ${manifest.type} configuration are readable there.
                Put the value in one of those options and read it there.
              ''
            else if declaredType != null && declaredType != name then
              throw (
                if builtins.elem declaredType (integrationsIn options) then
                  ''
                    ${what childName} is declared with a ${declaredType} configuration.
                    Declare it under `caisson.${declaredType}.configurations`.
                  ''
                else
                  ''
                    ${what childName} is declared with a ${declaredType} configuration, and a
                    ${declaredType} configuration cannot be declared beneath another
                    configuration.
                  ''
              )
            else
              finalized;
        in
        {
          exported = lib.mkOption {
            type = types.exported;
            default = configurations: configurations;
            defaultText = lib.literalMD "every configuration declared";
            description = ''
              Function that selects which of the ${name} configurations
              declared beneath this configuration it passes up. Receives
              `caisson.${name}.configurations` and returns the subset to
              export; `_: { }` exports none. What each selected configuration
              exports is merged into this configuration's `caisson.exports`.
            '';
          };
          configurations = lib.mkOption {
            type = types.configurations;
            default = { };
            apply = builtins.mapAttrs finalize;
            description = ''
              The ${name} configurations declared beneath this
              configuration, by name: each is what
              `lib.caisson.${name}.mkConfiguration` returns, and reads
              back as its manifest, finalized with the name it is declared
              under and this configuration as its parent. A configuration
              beneath sees this configuration without the configurations declared
              beneath it, so a definition that reads one of them is guarded
              with `!lib.caisson-core.evalManifest.childless`.
            '';
          };
        };

      # The integrations whose configurations an evaluation can hold
      # beneath it: those whose `configurationsModule` the evaluation
      # imports, read from its options. The module declares both
      # `configurations` and `exported`; `caisson.exports` declares
      # `configurations` alone.
      integrationsIn =
        options:
        builtins.filter (
          name:
          let
            declared = options.caisson.${name};
          in
          declared ? configurations && declared ? exported
        ) (builtins.attrNames (options.caisson or { }));

      # Of `integrationsIn options`, the integrations whose
      # `caisson.<integration>.configurations` a module of the evaluation
      # defines: those whose highest priority is above the priority of
      # an option default. The others hold no configurations, so neither
      # their configurations nor their `exported` selector is read, which
      # spares merging those options in every evaluation for every
      # integration the evaluation could hold.
      integrationsDeclaringIn =
        options:
        builtins.filter (name: options.caisson.${name}.configurations.highestPrio < 1500) (
          integrationsIn options
        );

      # The configurations an evaluated configuration declares beneath
      # it, by integration and then name, as the `children` an
      # integration's `evaluate` returns: the values of its
      # `caisson.<integration>.configurations` options, which finalize
      # each entry when read. An integration with none declared is left
      # out.
      childrenOf =
        { options, config }:
        filterAttrs (_: declared: declared != { }) (
          genAttrs (integrationsDeclaringIn options) (name: config.caisson.${name}.configurations)
        );

      # The nearest configuration above `manifest` whose integration is
      # one of `types`, null when there is none. The manifest records
      # the nearest ancestor of each integration; of those, the nearest
      # is the one with the most ancestors itself. A home reads its
      # machine this way, which is a NixOS or a darwin configuration.
      nearestOf =
        types: manifest:
        builtins.foldl' (
          found: type:
          let
            candidate = (manifest.nearest or { }).${type} or null;
          in
          if candidate == null then
            found
          else if found == null || builtins.length candidate.ancestors > builtins.length found.ancestors then
            candidate
          else
            found
        ) null types;

      # The nearest configuration above `manifest` that has an
      # activation (`mkModuleConfiguration`'s `activation`), as its
      # childless manifest, or null when there is none. A home inside a
      # NixOS machine finds the machine; an nvf configuration inside
      # that home finds the home.
      activatingAncestorOf =
        manifest:
        let
          found = builtins.filter (ancestor: (ancestor.activation or null) != null) (
            manifest.ancestors or [ ]
          );
        in
        if found == [ ] then null else last found;

      # The `activation` of a machine: a NixOS, darwin or system-manager
      # configuration. Its identity is its system, `toplevel`, null for
      # a configuration that builds none, as the nixos-minimal
      # integration can produce. Its marker is a file under `/etc`,
      # which the module `activation-marker` of its class writes.
      #
      # A machine is activated on its own host. A machine declared
      # inside another, such as an image, is applied on a different host
      # than the machine above, and the marker under `/etc` that it
      # finds there is its own, so it checks nothing above it:
      # `standsAlone`.
      machineActivation = {
        standsAlone = true;
        identity =
          manifest: if (manifest.outputs or { }) ? toplevel then manifest.outputs.toplevel.outPath else null;
        marker = _manifest: "/etc/caisson/marker.json";
      };

      # The file name of the marker of a configuration activated for a
      # user: the integration and the name the configuration is declared
      # under, with the characters the shell would read inside double
      # quotes, and the path separator, replaced.
      markerFileName =
        manifest:
        "${manifest.type}-${
          builtins.replaceStrings [ "/" "\"" "$" "`" "\\" ] [ "_" "_" "_" "_" "_" ] (
            manifest.name or "default"
          )
        }.json";

      # The digest a marker holds for an identity: the SHA-256 of its
      # store path. Computing the store path evaluates the childless
      # evaluation and builds nothing, and the digest refers to no store
      # path, so a marker that holds it depends on nothing. The digest
      # is compared, never read as a path.
      digestOf = identity: builtins.hashString "sha256" identity;

      # What the activation of the configuration of `manifest` writes
      # into its marker: the digest of the identity of its childless
      # evaluation (`digestOf`). `path` is the shell text of the path of
      # the marker. Null when the configuration has no activation or no
      # identity.
      markerOf =
        manifest:
        let
          activation = manifest.activation or null;
          childless = manifest.childlessManifest or manifest;
          identity = if activation == null then null else activation.identity childless;
        in
        if identity == null then
          null
        else
          {
            path = activation.marker childless;
            identity = digestOf identity;
            text = builtins.toJSON { identity = digestOf identity; };
          };

      # True when `entry`, an entry of `caisson.exports.configurations`
      # of the configuration of `manifest`, checks the marker of that
      # configuration when it is activated: the entry has an activation,
      # and the configuration is the nearest one above it that has an
      # activation.
      checksMarkerOf =
        manifest: entry:
        let
          ancestor = activatingAncestorOf entry.manifest;
        in
        (entry.manifest.activation or null) != null
        && !(entry.manifest.activation.standsAlone or false)
        && ancestor != null
        && builtins.length (ancestor.ancestors or [ ]) == builtins.length (manifest.ancestors or [ ]);

      # The shell text with which the activation of the configuration of
      # `manifest` checks for drift: it compares the marker of the
      # nearest configuration above with an activation against the
      # identity of that configuration as this configuration was built
      # for it, and prints a warning to standard error when the marker is
      # missing or names another identity. It does not stop the
      # activation. When that configuration activates this one, its
      # marker already belongs to the generation being activated, and
      # the check prints nothing. Empty when there is no such
      # configuration, or it has no identity. `jq` is the path of a jq
      # executable, and `optionText` names the option that turns the
      # warning off, for the message.
      driftCheckOf =
        { jq, optionText }:
        manifest:
        let
          ancestor =
            if (manifest.activation.standsAlone or false) then null else activatingAncestorOf manifest;
          expected = if ancestor == null then null else ancestor.activation.identity ancestor;
          marker = ancestor.activation.marker ancestor;
          above = "the ${ancestor.type} configuration `${ancestor.name or "(unnamed)"}`";
          self = "the ${manifest.type} configuration `${manifest.name or "(unnamed)"}`";
          # The digest of the identity, quoted for the shell. A digest is
          # hexadecimal, so quoting it whole is enough.
          escaped = "'${digestOf expected}'";
        in
        if expected == null then
          ""
        else
          ''
            _caissonMarker="${marker}"
            if [ ! -f "$_caissonMarker" ]; then
              echo "WARNING: $_caissonMarker does not exist." >&2
              echo "  ${self} is declared inside ${above}," >&2
              echo "  and the activation of ${above} has not recorded what it applied." >&2
              echo "  Activate ${above} as this configuration was built with it," >&2
              echo "  or set ${optionText} to false in ${self}." >&2
            else
              _caissonApplied="$(${jq} -r '.identity // empty' < "$_caissonMarker")"
              if [ "$_caissonApplied" != ${escaped} ]; then
                echo "WARNING: ${self} was built for a version of ${above} that differs from the version that is applied." >&2
                echo "  digest of the version applied (configurations declared inside it left out):" >&2
                echo "    ''${_caissonApplied:-unknown}" >&2
                echo "  digest of the version built for (configurations declared inside it left out):" >&2
                echo "    "${escaped} >&2
                echo "  Activate ${above} as this configuration was built with it," >&2
                echo "  or set ${optionText} to false in ${self}." >&2
              fi
            fi
          '';

      isManifest = value: builtins.isAttrs value && (value._type or null) == "caisson-manifest";

      # How a configuration is published: the `exportsTo` its
      # manifest records, or null for a configuration that is not
      # published under a name (structural, flake-parts).
      exportsToOf = manifest: manifest.exportsTo or null;

      showPath =
        path:
        builtins.concatStringsSep " / " (builtins.map (segment: "${segment.type} ${segment.name}") path);

      # The entry of a configuration that is passed up under `prefix`,
      # whose last segment holds the name it is passed up under: the
      # output attribute set and the value its `exportsTo` gives, and
      # its path, on which the name its `exportsTo` gives, where it
      # gives one, stands in place of that name.
      entryOf =
        prefix: manifest:
        let
          exportsTo = exportsToOf manifest;
          leaf = last prefix;
          named =
            if exportsTo ? name then
              exportsTo.name {
                inherit (leaf) name;
                inherit manifest;
              }
            else
              { value = leaf.name; };
        in
        {
          inherit manifest;
          inherit (exportsTo) attrset;
          single = exportsTo.single or false;
          bySystem = exportsTo.bySystem or false;
          system = manifest.system or null;
          value = exportsTo.value manifest;
          path = init prefix ++ [
            (
              leaf
              // {
                name =
                  if hasInfix "/" named.value then
                    throw ''
                      ${exportsTo.attrset}: the configuration at ${showPath prefix} is
                      named `${named.value}`, and a published name may not contain
                      `/`, which separates the parts of a name.
                    ''
                  else
                    named.value;
              }
            )
          ];
        }
        // (if named ? description then { inherit (named) description; } else { });

      # A published name, from the segments `caisson-core.elide` keeps
      # of a path: the segments in path order, separated by `/`. Every
      # name caisson publishes is written here.
      displayName = builtins.concatStringsSep "/";

      # The entries a configuration passes up for the configurations
      # declared beneath it, nested ones included: for each, its
      # manifest, the output attribute set it is published under, the
      # value published, and its path from here, a list of
      # `{ type, name }` segments. A configuration evaluated at a
      # system has that system above its name on the path. `selected`
      # is what each integration's `exported` selected, by integration
      # and then name, each value a manifest or the evaluations of a
      # configuration by system. A configuration whose manifest
      # records `exportsTo` is an entry, made here, where the name it
      # is passed up under is known, from what the manifest records;
      # and every configuration contributes the entries it passes up
      # in turn, with its segments in front. An entry carries all a
      # top needs to publish it.
      entriesOf =
        selected:
        builtins.concatMap (
          integration:
          builtins.concatMap (
            name:
            let
              finalized = selected.${integration}.${name};
              segment = {
                type = integration;
                inherit name;
              };
              beneath =
                if isManifest finalized then
                  [
                    {
                      prefix = [ segment ];
                      manifest = finalized;
                    }
                  ]
                else
                  builtins.map (system: {
                    prefix = [
                      {
                        type = "system";
                        name = system;
                      }
                      segment
                    ];
                    manifest = finalized.${system};
                  }) (builtins.attrNames finalized);
            in
            builtins.concatMap (
              { prefix, manifest }:
              (if exportsToOf manifest == null then [ ] else [ (entryOf prefix manifest) ])
              ++ builtins.map (entry: entry // { path = prefix ++ entry.path; }) (
                manifest.outputs.exports.configurations or [ ]
              )
            ) beneath
          ) (builtins.attrNames selected.${integration})
        ) (builtins.attrNames selected);

      # What a top publishes of the entries passed up to it, by the
      # output attribute set each entry carries and then name. The
      # top reads nothing but the entries. Within an attribute set the names come from
      # `caisson-core.elide` over the paths: a name that is alone stays
      # bare, and names that collide gain the segments that tell them
      # apart. Entries that still share a name are refused, with their
      # paths.
      #
      # An output that holds a single value (`colmenaHive`) is the value
      # of the entry named `default`, the entry whose `exportsTo` says
      # `single`. Any other entry for that output is refused, since the
      # output has no names to hold it under.
      #
      # An output whose entries' `exportsTo` says `bySystem` is keyed by
      # the system of each evaluation first, as flakes key `packages`
      # and `formatter`: `<attrset>.<system>`, holding the entries
      # evaluated at that system, named by the rules above over their
      # paths without the systems on them, or the single value there.
      publish =
        entries:
        let
          attrsets = unique (builtins.map (entry: entry.attrset) entries);
          publishIn =
            attrset:
            let
              members = builtins.filter (entry: entry.attrset == attrset) entries;
              keyed = builtins.filter (entry: entry.bySystem or false) members;
              systems = unique (builtins.map (entry: entry.system) keyed);
              withoutSystems =
                entry: entry // { path = builtins.filter (segment: segment.type != "system") entry.path; };
            in
            if keyed == [ ] then
              publishMembers attrset members
            else if builtins.length keyed != builtins.length members || builtins.elem null systems then
              throw ''
                ${attrset}: this output is keyed by system, and these configurations
                would be published there without a system:
                ${builtins.concatStringsSep "\n" (
                  builtins.map (entry: "  ${showPath entry.path}") (
                    builtins.filter (entry: !(entry.bySystem or false) || entry.system == null) members
                  )
                )}
              ''
            else
              genAttrs systems (
                system:
                publishMembers "${attrset}.${system}" (
                  builtins.map withoutSystems (builtins.filter (entry: entry.system == system) keyed)
                )
              );
          publishMembers =
            attrset: members:
            let
              names = builtins.map displayName (
                final.caisson-core.elide (builtins.map (entry: entry.path) members)
              );
              named = zipListsWith (name: entry: { inherit name entry; }) names members;
              clashing = builtins.filter (
                name: builtins.length (builtins.filter (other: other == name) names) > 1
              ) (unique names);
              single = builtins.any (entry: entry.single or false) members;
              notDefault = builtins.filter (entry: (last entry.path).name != "default") members;
            in
            if single then
              if builtins.length members == 1 && notDefault == [ ] then
                (builtins.head members).value
              else
                throw ''
                  ${attrset}: this output holds a single value, the configuration
                  declared under the name `default`, but these configurations would
                  be published there:
                  ${builtins.concatStringsSep "\n" (builtins.map (entry: "  ${showPath entry.path}") members)}
                ''
            else if clashing != [ ] then
              throw ''
                ${attrset}: these configurations would be published under the same
                name, `${builtins.head clashing}`:
                ${builtins.concatStringsSep "\n" (
                  builtins.map (item: "  ${showPath item.entry.path}") (
                    builtins.filter (item: item.name == builtins.head clashing) named
                  )
                )}
              ''
            else
              builtins.listToAttrs (
                builtins.map (item: {
                  inherit (item) name;
                  inherit (item.entry) value;
                }) named
              );
        in
        genAttrs attrsets publishIn;

      # What a tool reads from a top that is a configuration evaluated
      # per system, given its evaluations by system. They are named
      # like anything published, by `caisson-core.elide` over their
      # paths; the top is addressed by the file that returns it, so the
      # name of the top is left out of each. Where that leaves a single
      # evaluation with no name, the result is its value, the evaluated
      # configuration; otherwise it is the values by what is left of
      # each name.
      topValue =
        evaluations:
        let
          systems = builtins.attrNames evaluations;
          kept = final.caisson-core.elide (
            builtins.map (system: [
              {
                type = "system";
                name = system;
              }
              {
                inherit (evaluations.${system}) type;
                name = evaluations.${system}.name or "";
              }
            ]) systems
          );
          names = builtins.map (segments: displayName (init segments)) kept;
        in
        if names == [ "" ] then
          evaluations.${builtins.head systems}.value
        else
          builtins.listToAttrs (
            zipListsWith (name: system: {
              inherit name;
              inherit (evaluations.${system}) value;
            }) names systems
          );

      # An integration that evaluates a class another integration
      # owns, declared: `over` is the owning integration, reached
      # through the lib (`final.caisson.nixos`), and the class and its
      # registration form belong to that integration; the entry points
      # build on the composition that integration publishes, so the
      # evaluators cannot express different configurations from the
      # same arguments. The result is the value of `lib.caisson.<name>`:
      # the entry points and `extra`, no `mkModule`, and no class
      # declaration.
      mkAltIntegration =
        {
          over,
          mkConfiguration,
          mkConfigurationWithEcosystemArgs,
          # As for `mkIntegration`.
          top ? null,
          extra ? { },
        }:
        assert builtins.isAttrs over && over ? mkModule;
        {
          inherit mkConfiguration mkConfigurationWithEcosystemArgs;
        }
        // (if top == null then { } else { mkTopConfiguration = topConfiguration top mkConfiguration; })
        // extra;

    in
    {
      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit
            childrenOf
            displayName
            entriesOf
            configurationsModuleFor
            integrationsIn
            integrationsDeclaringIn
            nearestOf
            activatingAncestorOf
            machineActivation
            markerFileName
            markerOf
            checksMarkerOf
            driftCheckOf
            mkEvaluation
            publish
            topValue
            resolveEcosystemSrc
            mkIntegration
            mkAltIntegration
            frameworkModules
            mkModuleConfiguration
            moduleImportsOf
            pkgSetOf
            pkgSetsAt
            ;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
