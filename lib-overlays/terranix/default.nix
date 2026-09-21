# SPDX-License-Identifier: MIT
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
      mkModule = final.caisson-core.mkModule "terranix";

      selection = final.caisson.integrations;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "terranix";
        context = "caisson.terranix";
      };

      assertTerranixEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? terranixConfiguration then
          ecosystemSrc
        else
          throw "lib.caisson.terranix.mkConfiguration requires `ecosystemSrc.lib.terranixConfiguration`.";

      accepted = [
        "ecosystemSrc"
        "configModule"
        "moduleImports"
        "specialArgs"
        "pkgSets"
      ];
      hints = {
        modules = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
        extraArgs = "pass extra module arguments as `specialArgs`.";
        pkgs = "pass the package set as `pkgSets.pkgs`.";
        system = "pass the package set as `pkgSets.pkgs`; terranix evaluates against it.";
      };
      checkArgs = final.caisson.integrations.checkArgs {
        context = "lib.caisson.terranix.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.terranix.mkConfigurationWithEcosystemArgs";
      };
      checkOpenArgs = final.caisson.integrations.checkArgs {
        context = "lib.caisson.terranix.mkConfigurationWithEcosystemArgs";
        accepted = accepted ++ [ "ecosystemArgs" ];
        inherit hints;
      };

      # terranixConfiguration's arguments, composed from the caisson
      # arguments: pkgSets.pkgs is `pkgs` (terranix evaluates against
      # a package set, so mkConfiguration requires one), the selected
      # class modules and the config module are `modules`, and
      # specialArgs becomes terranix's `extraArgs` (framework defaults
      # first; the caller's win on conflict, as is normal in the Nix
      # ecosystem).
      compose =
        {
          ecosystemSrc ? null,
          configModule,
          moduleImports ? selection.defaultModuleImports,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          checkedEcosystemSrc = assertTerranixEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.libManifest or { };
          });
          registry = final.caisson-core.modules.terranix or { };
          # The framework module of the class: every registered `core`, forced.
          coreModules = selection.coreModules registry;
          selectedModules = moduleImports registry;
        in
        {
          inherit checkedEcosystemSrc;
          ecosystemArgs = (if pkgSets != null && pkgSets ? pkgs then { pkgs = pkgSets.pkgs; } else { }) // {
            modules = coreModules ++ selectedModules ++ [ configModule ];
            extraArgs = {
              inputs = closure-inputs;
            }
            // (if pkgSets != null then { inherit pkgSets; } else { })
            // specialArgs;
          };
        };

      mkConfiguration =
        rawArgs:
        let
          args = checkArgs rawArgs;
          composed = compose args;
        in
        if !(args ? pkgSets && args.pkgSets ? pkgs) then
          throw "lib.caisson.terranix.mkConfiguration requires `pkgSets.pkgs` to be defined."
        else
          composed.checkedEcosystemSrc.lib.terranixConfiguration composed.ecosystemArgs;

      # The same composition, then `ecosystemArgs` merged over the
      # evaluator call verbatim: everything terranixConfiguration takes
      # (system, pkgs, modules, extraArgs, strip_nulls) can be set or
      # replaced there; pkgSets is optional here since `system` or
      # `pkgs` may come that way.
      mkConfigurationWithEcosystemArgs =
        rawArgs:
        let
          args = checkOpenArgs rawArgs;
          composed = compose args;
        in
        composed.checkedEcosystemSrc.lib.terranixConfiguration (
          composed.ecosystemArgs // (args.ecosystemArgs or { })
        );
    in
    # This integration owns the `terranix` class.
    contributeClasses prev {
      terranix = {
        integration = "terranix";
        inherit mkModule;
      };
    }
    // {
      caisson = (prev.caisson or { }) // {
        terranix = ((prev.caisson or { }).terranix or { }) // {
          inherit
            mkConfiguration
            mkConfigurationWithEcosystemArgs
            mkModule
            ;
        };
      };
    };

}
