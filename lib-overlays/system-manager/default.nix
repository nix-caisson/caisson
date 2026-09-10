# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "systemManager";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "system-manager";
        context = "caisson.system-manager";
        resolve = final.caisson-core.resolve;
      };

      assertSystemManagerEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeSystemConfig then
          ecosystemSrc
        else
          throw "lib.caisson.system-manager.mkConfiguration requires `ecosystemSrc.lib.makeSystemConfig`.";

      mkCommonArgs =
        args@{
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.systemManager or { });
          # system-manager instantiates its own nixpkgs from
          # `nixpkgs.hostPlatform`; a supplied package set seeds that
          # platform (an explicit hostPlatform wins) and rides along as
          # the `pkgSets` module argument.
          pkgSetsModule =
            if pkgSets != null && pkgSets ? pkgs then
              [
                {
                  _file = "caisson-system-manager:pkgSets";
                  nixpkgs.hostPlatform = final.mkDefault pkgSets.pkgs.stdenv.hostPlatform.system;
                }
              ]
            else
              [ ];
        in
        {
          modules = selectedModules ++ pkgSetsModule ++ [ configModule ];
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          specialArgs = {
            inputs = closure-inputs;
          }
          // (if pkgSets != null then { inherit pkgSets; } else { })
          // specialArgs;
        };

      accepted = [
        "ecosystemSrc"
        "configModule"
        "moduleImports"
        "specialArgs"
        "pkgSets"
      ];
      hints = {
        modules = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
        extraSpecialArgs = "pass extra module arguments as `specialArgs`.";
      };
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.system-manager.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.system-manager.mkConfigurationUnsupervised";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.system-manager.mkConfigurationUnsupervised";
        accepted = accepted ++ [ "evaluatorArgs" ];
        inherit hints;
      };
      # makeSystemConfig's arguments, composed from the caisson arguments,
      # plus the compatibility bridge below.
      compose =
        args:
        let
          checkedEcosystemSrc = assertSystemManagerEcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = final.caisson-core.manifest or { };
          });
          common = mkCommonArgs args;

          # system-manager imports selected NixOS modules from its own
          # nixpkgs input; current nixos-unstable restructured
          # nixos/modules/config/nix.nix in two ways system-manager's
          # module set (tip 48d4734) does not absorb. Both are bridged
          # here, where every system-manager eval composes.
          # Delete the bridge when upstream absorbs the restructure: each
          # half fails loudly (duplicate declaration / unused disable)
          # when its reason disappears.
          smNixpkgs = checkedEcosystemSrc.inputs.nixpkgs;
          nixosNixModuleText = builtins.readFile "${smNixpkgs}/nixos/modules/config/nix.nix";

          # (1) That module now defines `services.displayManager.hiddenUsers`
          # (hiding nixbld users from display managers), an option nothing
          # in a system-manager eval declares, which is fatal structurally,
          # before any mkIf can discharge it. Declare the sink, following
          # system-manager's own ignored-options pattern: no display
          # manager exists in a system-manager config. The sink retires
          # itself when system-manager's ignored-options file (the likely
          # fix site) mentions the option; a fix landing anywhere else
          # surfaces as a duplicate declaration at that pin's gate.
          smIgnoredOptionsText = builtins.readFile "${checkedEcosystemSrc}/nix/modules/upstream/nixpkgs/default.nix";
          smDeclaresDisplayManager = final.hasInfix "displayManager" smIgnoredOptionsText;
          displayManagerSinkModule = {
            _file = "caisson-system-manager:nixpkgs-compat-sink";
            imports = [
              (
                { lib, ... }:
                {
                  options.services.displayManager.hiddenUsers = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Compatibility sink; system-manager configs have no display manager.";
                  };
                }
              )
            ];
          };

          # (2) That module now also declares `nix.enable`/`nix.package`
          # itself, colliding with system-manager's stub declarations of
          # the same options (nix/modules/upstream/nixpkgs/nix.nix, which
          # predates them landing in the NixOS module). When the NixOS
          # module owns the options, disable the stub and re-provide the
          # two config facts it carried: nix.conf must replace a foreign
          # distro's existing file, flakes stay on by default, and
          # `nix.enable` keeps the stub's off-by-default (the NixOS
          # declaration defaults it on, which would materialize nixbld
          # users on hosts whose configs did not ask for nix management).
          nixosNixOwnsDaemonOptions = final.hasInfix "services.displayManager" nixosNixModuleText;
          nixStubReplacementModule = {
            _file = "caisson-system-manager:nixpkgs-compat-nix-stub";
            disabledModules = [ "${checkedEcosystemSrc}/nix/modules/upstream/nixpkgs/nix.nix" ];
            imports = [
              (
                { config, lib, ... }:
                {
                  config = lib.mkMerge [
                    { nix.enable = lib.mkDefault false; }
                    (lib.mkIf config.nix.enable {
                      environment.etc."nix/nix.conf".replaceExisting = true;
                      nix.settings.experimental-features = lib.mkDefault [
                        "nix-command"
                        "flakes"
                      ];
                    })
                  ];
                }
              )
            ];
          };

          compatModules =
            final.optional (!smDeclaresDisplayManager) displayManagerSinkModule
            ++ final.optional nixosNixOwnsDaemonOptions nixStubReplacementModule;
        in
        {
          inherit checkedEcosystemSrc;
          evaluatorArgs = {
            inherit (common) specialArgs;
            modules = common.modules ++ compatModules;
          };
        };

      mkConfiguration =
        rawArgs:
        let
          composed = compose (checkArgs rawArgs);
        in
        composed.checkedEcosystemSrc.lib.makeSystemConfig composed.evaluatorArgs;

      # The same composition, then `evaluatorArgs` merged over the
      # evaluator call verbatim: everything makeSystemConfig takes
      # (modules, overlays, specialArgs, allowUnsupportedNixpkgs) can be
      # set or replaced there.
      mkConfigurationUnsupervised =
        rawArgs:
        let
          args = checkOpenArgs rawArgs;
          composed = compose args;
        in
        composed.checkedEcosystemSrc.lib.makeSystemConfig (
          composed.evaluatorArgs // (args.evaluatorArgs or { })
        );
    in
    {
      caisson = (prev.caisson or { }) // {
        system-manager = ((prev.caisson or { }).system-manager or { }) // {
          inherit
            mkConfiguration
            mkConfigurationUnsupervised
            mkModule
            ;
        };
      };
    };

}
