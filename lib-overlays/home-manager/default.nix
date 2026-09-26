# SPDX-License-Identifier: MIT
#
# The home-manager integration: it owns the `homeManager`
# class and evaluates it with home-manager's standalone evaluator,
# `modules/default.nix` of the home-manager source. Beside the entry
# points it carries the adapters that place a home-manager
# configuration inside a NixOS one, and the source metadata the
# activation coherence check compares.
{
  contributeClasses,
  entries,
  mkLibOverlay,
  ...
}:
{

  imports = [
    entries.nixpkgs-lib
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson.home-manager.mkModule;
      mkNixosModule = final.caisson-core.mkModule "nixos";

      selection = final.caisson.integrations;
      registry = final.caisson-core.modules.homeManager or { };
      # The framework module of the class: every registered `core`,
      # forced into every home-manager evaluation.
      coreModules = selection.coreModules registry;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "home-manager";
        context = "caisson.home-manager";
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.libManifest or { };
        };

      assertPkgSets =
        pkgSets:
        if pkgSets ? pkgs then
          pkgSets
        else
          throw "lib.caisson.home-manager.mkConfiguration requires `pkgSets.pkgs` to be defined.";

      resolveOutPath =
        value:
        if value == null then
          null
        else if builtins.isAttrs value && value ? outPath then
          value.outPath
        else
          toString value;

      # Provenance derives from what composes: the ecosystem source
      # handed to the entry point and the nixpkgs the package set was
      # instantiated from.
      mkSourceMeta =
        {
          profileName,
          hostName ? null,
          hostKind ? "standalone",
          schemaVersion ? 3,
          self ? null,
          nixpkgsOutPath ? null,
          homeManagerOutPath ? null,
          baseSystem ? null,
        }:
        let
          canonical = {
            inherit
              hostKind
              hostName
              profileName
              schemaVersion
              ;
            selfOutPath = resolveOutPath self;
            inherit nixpkgsOutPath homeManagerOutPath;
            # The out path of the host's NixOS system *without* home-manager:
            # the coherence check compares this string, so it must not carry
            # derivation context; stripping it keeps embedding from forcing
            # a build.
            baseSystemOutPath =
              if baseSystem == null then
                null
              else
                builtins.unsafeDiscardStringContext (resolveOutPath baseSystem);
          };
        in
        canonical
        // {
          fingerprint = builtins.hashString "sha256" (builtins.toJSON canonical);
        };

      mkSourceMetaModule =
        sourceMeta:
        mkModule (
          { ... }:
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            _file = "caisson-home-manager/sourceMetaModule";
            options.caisson-home-manager = {
              # No `default`: the module system counts an option default as a
              # definition in the readOnly check (lib/modules.nix
              # evalOptionValue prepends it to defs'), so readOnly + default
              # throws "set multiple times" the moment anything reads the
              # option.  This module always defines the value anyway.
              sourceMeta = lib.mkOption {
                type = lib.types.attrs;
                readOnly = true;
              };

              driftWarning = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Warn during activation if host source metadata diverges from this configuration.";
              };
            };

            config = {
              caisson-home-manager.sourceMeta = sourceMeta;

              home.activation.checkSourceCoherence = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
                _marker="/etc/caisson-home-manager/source.json"
                _expected_base="${
                  if (sourceMeta.baseSystemOutPath or null) != null then sourceMeta.baseSystemOutPath else ""
                }"
                if ${
                  if config.caisson-home-manager.driftWarning then "true" else "false"
                } && [ -n "$_expected_base" ]; then
                  if [ ! -f "$_marker" ]; then
                    echo "WARNING: no source marker at $_marker." >&2
                    echo "  This profile expects the NixOS generation to manage home-manager, but the" >&2
                    echo "  active system was built without the caisson-home-manager adapter (or has" >&2
                    echo "  never been rebuilt since it was enabled).  Run nixos-rebuild to converge." >&2
                  else
                    _host_base="$(${lib.getExe' pkgs.jq "jq"} -r '.baseSystemOutPath // empty' < "$_marker")"
                    if [ -z "$_host_base" ]; then
                      echo "WARNING: $_marker has no baseSystemOutPath." >&2
                      echo "  The active NixOS generation predates the base-system coherence scheme." >&2
                      echo "  Run nixos-rebuild to refresh it." >&2
                    elif [ "$_host_base" != "$_expected_base" ]; then
                      echo "WARNING: source drift detected." >&2
                      echo "  active system's base (non-home-manager) closure:" >&2
                      echo "    $_host_base" >&2
                      echo "  this configuration expects:" >&2
                      echo "    $_expected_base" >&2
                      echo "  The system differs from source in non-home-manager ways; run nixos-rebuild" >&2
                      echo "  to converge, or set caisson-home-manager.driftWarning = false." >&2
                    fi
                  fi
                fi
              '';
            };
          }
        );

      mkCommonArgs =
        {
          ecosystemSrc ? null,
          pkgSets,
          configModule,
          moduleImports ? selection.defaultModuleImports,
          specialArgs ? { },
          osConfig ? null,
          check ? true,
          minimal ? false,
          sourceMeta ? null,
          ...
        }:
        let
          checkedPkgSets = assertPkgSets pkgSets;
          selectedModules = moduleImports registry;
          hmSource = resolveOutPath (resolveSrc ecosystemSrc);
          resolvedSourceMeta =
            if sourceMeta != null then
              sourceMeta
            else
              mkSourceMeta {
                profileName = "default";
                homeManagerOutPath = hmSource;
                nixpkgsOutPath = resolveOutPath (checkedPkgSets.pkgs.path or null);
              };
        in
        {
          inherit
            check
            minimal
            ;
          sourceMeta = resolvedSourceMeta;
          configuration = {
            imports =
              coreModules
              ++ selectedModules
              ++ [
                configModule
                (mkSourceMetaModule resolvedSourceMeta)
                { programs.home-manager.path = final.mkDefault hmSource; }
              ];
          };
          pkgs = checkedPkgSets.pkgs;
          # Framework defaults first; the values the caller passed win on
          # conflict. home-manager names these extraSpecialArgs; the
          # caisson name is specialArgs.
          extraSpecialArgs = {
            pkgSets = checkedPkgSets;
            inherit osConfig;
            sourceMeta = resolvedSourceMeta;
          }
          // specialArgs;
          evaluatorPath = "${hmSource}/modules";
        };

      # The evaluator's call, from the composition above: everything
      # home-manager's evaluator takes (configuration, pkgs, lib,
      # minimal, check, extraSpecialArgs) can be set or replaced
      # through the twin's `ecosystemArgs`.
      compose =
        args:
        let
          common = mkCommonArgs args;
        in
        common
        // {
          ecosystemArgs = {
            inherit (common)
              check
              configuration
              extraSpecialArgs
              minimal
              pkgs
              ;
          };
        };

      evaluate = composed: callArgs: (import composed.evaluatorPath) callArgs;

      mkConfiguration = final.caisson.home-manager.mkConfiguration;

      mkStandaloneAdapter =
        args@{
          moduleImports ? selection.defaultModuleImports,
          ...
        }:
        let
          selectedModules = moduleImports registry;
        in
        {
          homeModules = coreModules ++ selectedModules;
          buildHome = configModule: mkConfiguration (args // { inherit configModule moduleImports; });
        };

      # The adapter's signature is open, its extras being NixOS-module
      # options rather than evaluator arguments; home-manager's
      # `extraSpecialArgs` spelling is refused with a pointer to
      # `specialArgs`.
      mkNixosAdapter =
        rawArgs:
        if rawArgs ? extraSpecialArgs then
          throw "lib.caisson.home-manager.mkNixosAdapter does not accept `extraSpecialArgs`: pass extra module arguments as `specialArgs`."
        else
          mkNixosAdapterChecked rawArgs;
      mkNixosAdapterChecked =
        args@{
          users,
          ecosystemSrc ? null,
          hostName ? null,
          hostKind ? "nixos",
          # The same host's NixOS system evaluated *without* this adapter
          # module.  Its out path is what standalone home-manager activations
          # compare against to detect non-home-manager drift; without it the
          # marker cannot vouch for coherence.
          baseSystem ? null,
          sourceMeta ? null,
          moduleImports ? selection.defaultModuleImports,
          sharedModules ? [ ],
          useGlobalPkgs ? true,
          useUserPackages ? true,
          # How the NixOS generation triggers home-manager activation:
          #
          # "upstream": home-manager's nixos module delivery (system
          # units at boot).  Fine when the OS declares the users and their
          # homes are available at boot.
          #
          # "user-service": a complete user unit in /etc, gated by
          # ConditionUser, that runs `activate` when the user's service
          # manager starts.  It leaves `users.users` untouched, so it is safe for
          # systemd-homed hosts, where a NixOS-created passwd entry would
          # conflict with the homed user record and the home directory is
          # only mounted at login anyway.  Limited to one user: a single
          # shared unit cannot carry per-user ExecStarts.
          activationMode ? "upstream",
          specialArgs ? { },
          ...
        }:
        assert final.assertMsg (builtins.elem activationMode [
          "upstream"
          "user-service"
        ]) "mkNixosAdapter: activationMode must be \"upstream\" or \"user-service\".";
        assert final.assertMsg (
          activationMode != "user-service" || builtins.length (builtins.attrNames users) == 1
        ) "mkNixosAdapter: activationMode \"user-service\" supports exactly one user.";
        mkNixosModule (
          { ... }:
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            checkedPkgSets = assertPkgSets (if args ? pkgSets then args.pkgSets else { inherit pkgs; });
            sharedClassModules = coreModules ++ moduleImports registry;
            hmSource = resolveOutPath (resolveSrc ecosystemSrc);
            resolvedSourceMeta =
              if sourceMeta != null then
                sourceMeta
              else
                mkSourceMeta {
                  profileName = "hosted";
                  inherit
                    baseSystem
                    hostKind
                    hostName
                    ;
                  homeManagerOutPath = hmSource;
                  nixpkgsOutPath = resolveOutPath (checkedPkgSets.pkgs.path or null);
                };
            sourceMetaModule = mkSourceMetaModule resolvedSourceMeta;

            mkUserConfig =
              _username: userArgs:
              let
                userModuleImports = userArgs.moduleImports or (_modules: [ ]);
                userClassModules = userModuleImports registry;
                configModule =
                  if userArgs ? configModule then
                    userArgs.configModule
                  else
                    throw "mkNixosAdapter requires `users.<name>.configModule`.";
              in
              {
                imports = userClassModules ++ [ configModule ];
              };
          in
          if activationMode == "user-service" then
            # No home-manager NixOS module at all: it cannot evaluate without
            # a `users.users.<name>` entry (its injected defs dereference the
            # user record), and creating one would conflict with
            # systemd-homed's ownership of the account.  Instead each user is
            # evaluated with the same standalone evaluator (mkConfiguration)
            # that `home-manager switch` uses (the embedded generation is the
            # standalone one by construction), and a complete /etc user unit
            # runs its activation when the user's service manager starts.
            (
              let
                username = builtins.head (builtins.attrNames users);
                userActivations = builtins.mapAttrs (
                  _username: userArgs:
                  (mkConfiguration {
                    inherit ecosystemSrc specialArgs;
                    pkgSets = checkedPkgSets;
                    configModule =
                      if userArgs ? configModule then
                        userArgs.configModule
                      else
                        throw "mkNixosAdapter requires `users.<name>.configModule`.";
                    moduleImports = userArgs.moduleImports or moduleImports;
                    sourceMeta = userArgs.sourceMeta or resolvedSourceMeta;
                  }).activationPackage
                ) users;
              in
              {
                options.caisson-home-manager.hostedActivations = lib.mkOption {
                  type = lib.types.attrsOf lib.types.package;
                  readOnly = true;
                  description = ''
                    Per-user home-manager activation packages embedded in this
                    NixOS generation (activationMode = "user-service").
                  '';
                };

                config = {
                  caisson-home-manager.hostedActivations = userActivations;

                  systemd.user.services.home-manager = {
                    description = "Home Manager activation for ${username}";
                    unitConfig = {
                      ConditionUser = username;
                      RequiresMountsFor = "%h";
                    };
                    environment = {
                      # Mirrors upstream's base unit: Qt tools invoked during
                      # activation must not require a display.
                      QT_QPA_PLATFORM = "offscreen";
                    };
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      TimeoutStartSec = "5m";
                      SyslogIdentifier = "hm-activate-${username}";
                      # A login shell, as upstream's system units use: the
                      # standalone activation script expects the user's normal
                      # environment (nix on PATH to update its profile).
                      ExecStart = pkgs.writeScript "hm-user-activate-${username}" ''
                        #! ${pkgs.runtimeShell} -el
                        exec ${userActivations.${username}}/activate
                      '';
                    };
                    wantedBy = [ "default.target" ];
                  };

                  environment.etc."caisson-home-manager/source.json".text = builtins.toJSON resolvedSourceMeta;
                };
              }
            )
          else
            {
              imports = [ "${hmSource}/nixos" ];

              "home-manager" = {
                inherit
                  useGlobalPkgs
                  useUserPackages
                  ;
                # Framework defaults first; the values the caller passed
                # win on conflict.
                extraSpecialArgs = {
                  pkgSets = checkedPkgSets;
                  sourceMeta = resolvedSourceMeta;
                }
                // specialArgs;
                # The extra entries match the standalone defaults of
                # mkCommonArgs, so a user generation inside the NixOS
                # configuration evaluates to the same derivation as the
                # standalone profile built from the same source.
                sharedModules =
                  sharedModules
                  ++ sharedClassModules
                  ++ [
                    sourceMetaModule
                    { programs.home-manager.path = final.mkDefault hmSource; }
                    (
                      {
                        config,
                        lib,
                        pkgs,
                        ...
                      }:
                      {
                        config = lib.mkMerge [
                          # Hosted default is the OS's i18n.glibcLocales;
                          # standalone default is pkgs.glibcLocales.
                          { i18n.glibcLocales = lib.mkDefault pkgs.glibcLocales; }
                          # Upstream skips the home-manager CLI for submodule
                          # evaluations, but the standalone CLI must
                          # survive a nixos-rebuild "revert" or the user cannot
                          # layer standalone switches afterwards.
                          (lib.mkIf (config.programs.home-manager.enable && config.submoduleSupport.enable) {
                            home.packages = [ config.programs.home-manager.package ];
                          })
                        ];
                      }
                    )
                  ];
                users = lib.mapAttrs mkUserConfig users;
              };

              environment.etc."caisson-home-manager/source.json".text = builtins.toJSON resolvedSourceMeta;
            }
        );

      assertSourceCoherence =
        {
          hostSourceMeta,
          targetSourceMeta,
          allowDrift ? false,
        }:
        let
          hostFp = hostSourceMeta.fingerprint or null;
          targetFp = targetSourceMeta.fingerprint or null;
        in
        if allowDrift then
          true
        else if hostFp == null || targetFp == null then
          throw "Source coherence check failed: fingerprint missing from host or target metadata."
        else if hostFp == targetFp then
          true
        else
          throw ''
            Source coherence check failed.
            host fingerprint: ${hostFp}
            target fingerprint: ${targetFp}
          '';
      integration = selection.mkIntegration {
        name = "home-manager";
        class = "homeManager";
        accepted = [
          "osConfig"
          "check"
          "minimal"
          "sourceMeta"
        ];
        # What `mkCommonArgs` destructures without a default. The
        # package set is checked twice, for two different mistakes:
        # the signature reports `pkgSets` absent, `assertPkgSets`
        # reports a `pkgSets` that carries no `pkgs`.
        required = [
          "pkgSets"
          "configModule"
        ];
        hints = {
          configuration = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
          pkgs = "pass the package set as `pkgSets.pkgs`.";
          extraSpecialArgs = "pass extra module arguments as `specialArgs`.";
        };
        inherit compose evaluate;
        extra = {
          inherit
            assertSourceCoherence
            mkNixosAdapter
            mkSourceMeta
            mkStandaloneAdapter
            ;
        };
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        home-manager = integration.namespace;
      };
    };

}
