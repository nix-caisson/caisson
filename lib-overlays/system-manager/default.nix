# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkSystemManagerModule = final.caisson.mkModule "systemManager";

      assertSystemManagerEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeSystemConfig then
          ecosystemSrc
        else
          throw "lib.caisson.system-manager.mkSystemConfig requires `ecosystemSrc.lib.makeSystemConfig`.";

      mkCommonArgs =
        args@{
          modules ? [ ],
          moduleImports ? modules: modules,
          specialArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson.modules.systemManager or { });
        in
        {
          modules = (builtins.attrValues selectedModules) ++ modules;
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          specialArgs = {
            inputs = closure-inputs;
          }
          // specialArgs;
        };

      mkSystemConfig =
        args@{
          ecosystemSrc,
          ...
        }:
        let
          checkedEcosystemSrc = assertSystemManagerEcosystemSrc ecosystemSrc;
          common = mkCommonArgs args;
          passthroughArgs = builtins.removeAttrs args [
            "ecosystemSrc"
            "modules"
            "moduleImports"
            "specialArgs"
          ];

          # system-manager imports selected NixOS modules from its own
          # nixpkgs input; current nixos-unstable restructured
          # nixos/modules/config/nix.nix in two ways system-manager's
          # module set (tip 48d4734) does not absorb. Both are bridged
          # here, at the one place every system-manager eval composes.
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
          # users on hosts whose configs never asked for nix management).
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
        checkedEcosystemSrc.lib.makeSystemConfig (
          passthroughArgs
          // {
            inherit (common) specialArgs;
            modules = common.modules ++ compatModules;
          }
        );
    in
    {
      caisson = (prev.caisson or { }) // {
        system-manager = ((prev.caisson or { }).system-manager or { }) // {
          inherit
            mkSystemConfig
            mkSystemManagerModule
            ;
        };
      };
    };

}
