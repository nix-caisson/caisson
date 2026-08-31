# SPDX-License-Identifier: MIT
{ ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkHomeManagerModule = final.caisson-core.mkModule "homeManager";
      mkNixosModule = final.caisson-core.mkModule "nixos";

      assertPkgSets =
        pkgSets:
        if pkgSets ? pkgs then
          pkgSets
        else
          throw "lib.caisson.home-manager.mkHomeConfiguration requires `pkgSets.pkgs` to be defined.";

      resolveOutPath =
        value:
        if value == null then
          null
        else if builtins.isAttrs value && value ? outPath then
          value.outPath
        else
          toString value;

      # Provenance derives from what actually composes: the ecosystem
      # source handed to the entry point and the nixpkgs the package set
      # was instantiated from.  Nothing falls back to pinned inputs.
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
            # derivation context (embedding it may never force a build).
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
        mkHomeManagerModule (
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
        args@{
          ecosystemSrc,
          pkgSets,
          configModule,
          moduleImports ? modules: modules,
          extraSpecialArgs ? { },
          osConfig ? null,
          check ? true,
          minimal ? false,
          sourceMeta ? null,
          ...
        }:
        let
          checkedPkgSets = assertPkgSets pkgSets;
          selectedModules = moduleImports (final.caisson-core.modules.homeManager or { });
          hmSource = resolveOutPath ecosystemSrc;
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
            imports = (builtins.attrValues selectedModules) ++ [
              configModule
              (mkSourceMetaModule resolvedSourceMeta)
              { programs.home-manager.path = final.mkDefault hmSource; }
            ];
          };
          pkgs = checkedPkgSets.pkgs;
          # Framework defaults first; caller's extraSpecialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          extraSpecialArgs = {
            pkgSets = checkedPkgSets;
            inherit osConfig;
            sourceMeta = resolvedSourceMeta;
          }
          // extraSpecialArgs;
          evaluatorPath = "${hmSource}/modules";
        };

      mkHomeConfiguration =
        args:
        let
          common = mkCommonArgs args;
          evaluator = import common.evaluatorPath;
        in
        evaluator {
          inherit (common)
            check
            configuration
            extraSpecialArgs
            minimal
            pkgs
            ;
        };

      mkHomeConfigurationMinimal = args: mkHomeConfiguration (args // { minimal = true; });

      mkStandaloneAdapter =
        args@{
          moduleImports ? modules: modules,
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.homeManager or { });
        in
        {
          homeModules = selectedModules;
          buildHome = configModule: mkHomeConfiguration (args // { inherit configModule moduleImports; });
        };

      mkNixosAdapter =
        args@{
          users,
          ecosystemSrc,
          hostName ? null,
          hostKind ? "nixos",
          # The same host's NixOS system evaluated *without* this adapter
          # module.  Its out path is what standalone home-manager activations
          # compare against to detect non-home-manager drift; without it the
          # marker cannot vouch for coherence.
          baseSystem ? null,
          sourceMeta ? null,
          moduleImports ? modules: modules,
          sharedModules ? [ ],
          useGlobalPkgs ? true,
          useUserPackages ? true,
          # How the NixOS generation triggers home-manager activation:
          #
          # "upstream": home-manager's own nixos module delivery (system
          # units at boot).  Fine when the OS declares the users and their
          # homes are available at boot.
          #
          # "user-service": a complete user unit in /etc, gated by
          # ConditionUser, that runs `activate` when the user's service
          # manager starts.  Never touches `users.users`, so it is safe for
          # systemd-homed hosts, where a NixOS-created passwd entry would
          # conflict with the homed user record and the home directory is
          # only mounted at login anyway.  Currently limited to exactly one
          # hosted user (one shared unit cannot carry per-user ExecStarts).
          activationMode ? "upstream",
          extraSpecialArgs ? { },
          ...
        }:
        assert final.assertMsg (builtins.elem activationMode [
          "upstream"
          "user-service"
        ]) "mkNixosAdapter: activationMode must be \"upstream\" or \"user-service\".";
        assert final.assertMsg (
          activationMode != "user-service" || builtins.length (builtins.attrNames users) == 1
        ) "mkNixosAdapter: activationMode \"user-service\" currently supports exactly one hosted user.";
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
            sharedClassModules = builtins.attrValues (
              moduleImports (final.caisson-core.modules.homeManager or { })
            );
            hmSource = resolveOutPath ecosystemSrc;
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
                userModuleImports = userArgs.moduleImports or (_modules: { });
                userClassModules = builtins.attrValues (
                  userModuleImports (final.caisson-core.modules.homeManager or { })
                );
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
            # evaluated with the same standalone evaluator (mkHomeConfiguration)
            # that `home-manager switch` uses (the embedded generation is the
            # standalone one by construction), and a complete /etc user unit
            # runs its activation when the user's service manager starts.
            (
              let
                username = builtins.head (builtins.attrNames users);
                userActivations = builtins.mapAttrs (
                  _username: userArgs:
                  (mkHomeConfiguration {
                    inherit ecosystemSrc extraSpecialArgs;
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
                      # environment (nix on PATH for its own profile update).
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
                # Framework defaults first; caller's extraSpecialArgs wins on conflict.
                # This is intentional and normal in the Nix ecosystem.
                extraSpecialArgs = {
                  pkgSets = checkedPkgSets;
                  sourceMeta = resolvedSourceMeta;
                }
                // extraSpecialArgs;
                # The extra entries mirror mkCommonArgs/standalone defaults so a
                # hosted user generation evaluates to the same derivation as the
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
                          # (hosted) evaluations, but the standalone CLI must
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
    in
    {
      caisson = (prev.caisson or { }) // {
        home-manager = ((prev.caisson or { }).home-manager or { }) // {
          inherit
            assertSourceCoherence
            mkHomeConfiguration
            mkHomeConfigurationMinimal
            mkHomeManagerModule
            mkNixosAdapter
            mkSourceMeta
            mkStandaloneAdapter
            ;
        };
      };
    };

}
