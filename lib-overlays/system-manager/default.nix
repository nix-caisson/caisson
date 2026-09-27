# SPDX-License-Identifier: MIT
#
# The system-manager integration: it owns the `systemManager`
# class and evaluates it with `makeSystemConfig` from the
# system-manager flake.
{
  closure-inputs,
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
      selection = final.caisson.integrations;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "system-manager";
        context = "caisson.system-manager";
      };

      assertSystemManagerEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeSystemConfig then
          ecosystemSrc
        else
          throw "lib.caisson.system-manager.mkConfiguration requires `ecosystemSrc.lib.makeSystemConfig`.";

      mkCommonArgs =
        {
          configModule,
          moduleImports ? selection.defaultModuleImports,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          registry = final.caisson-core.modules.systemManager or { };
          # The framework module of the class: every registered `core`, forced.
          coreModules = selection.coreModules registry;
          selectedModules = moduleImports registry;
          # system-manager instantiates nixpkgs itself from
          # `nixpkgs.hostPlatform`; a supplied package set seeds that
          # platform (an explicit hostPlatform wins) and is passed as
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
          modules = coreModules ++ selectedModules ++ pkgSetsModule ++ [ configModule ];
          # Framework defaults first; the values the caller passed win
          # on conflict.
          specialArgs = {
            inputs = closure-inputs;
          }
          // (if pkgSets != null then { inherit pkgSets; } else { })
          // specialArgs;
        };

      # makeSystemConfig's arguments, composed from the caisson arguments,
      # plus the compatibility bridge below.
      compose =
        args:
        let
          src = assertSystemManagerEcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = final.caisson-core.libManifest or { };
          });
          common = mkCommonArgs args;

          # system-manager imports selected NixOS modules from the
          # nixpkgs input pinned in its flake; current nixos-unstable
          # restructured nixos/modules/config/nix.nix in two ways
          # system-manager's module set (tip 48d4734) does not absorb. Both are bridged
          # here, where every system-manager eval composes.
          # Delete the bridge when upstream absorbs the restructure: each
          # half fails loudly (duplicate declaration / unused disable)
          # when its reason disappears.
          smNixpkgs = src.inputs.nixpkgs;
          nixosNixModuleText = builtins.readFile "${smNixpkgs}/nixos/modules/config/nix.nix";

          # (1) That module now defines `services.displayManager.hiddenUsers`
          # (hiding nixbld users from display managers), an option nothing
          # in a system-manager eval declares, which is fatal structurally,
          # before any mkIf can discharge it. Declare the sink, following
          # system-manager's ignored-options pattern: no display
          # manager exists in a system-manager config. The sink retires
          # itself when the ignored-options file of system-manager (the
          # likely fix site) mentions the option; a fix landing anywhere
          # else surfaces as a duplicate declaration at that pin's gate.
          smIgnoredOptionsText = builtins.readFile "${src}/nix/modules/upstream/nixpkgs/default.nix";
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
            disabledModules = [ "${src}/nix/modules/upstream/nixpkgs/nix.nix" ];
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
          inherit src;
          ecosystemArgs = {
            inherit (common) specialArgs;
            modules = common.modules ++ compatModules;
          };
        };

      # Everything makeSystemConfig takes (modules, overlays,
      # specialArgs, allowUnsupportedNixpkgs) can be set or replaced
      # through the twin's `ecosystemArgs`.
      evaluate = composed: callArgs: composed.src.lib.makeSystemConfig callArgs;

      integration = selection.mkIntegration {
        name = "system-manager";
        class = "systemManager";
        # What `mkCommonArgs` destructures without a default;
        # system-manager instantiates nixpkgs itself, so `pkgSets`
        # defaults to null.
        required = [ "configModule" ];
        hints = {
          extraSpecialArgs = "pass extra module arguments as `specialArgs`.";
        };
        inherit compose evaluate;
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        system-manager = integration.namespace;
      };
    };

}
