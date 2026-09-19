# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "terranix";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "terranix";
        context = "caisson.terranix";
        resolve = final.caisson-core.resolve;
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
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.terranix.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.terranix.mkConfigurationWithEcosystemArgs";
      };
      checkOpenArgs = import ../check-args.nix {
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
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          checkedEcosystemSrc = assertTerranixEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.manifest or { };
          });
          selectedModules = moduleImports (final.caisson-core.modules.terranix or { });
        in
        {
          inherit checkedEcosystemSrc;
          ecosystemArgs = (if pkgSets != null && pkgSets ? pkgs then { pkgs = pkgSets.pkgs; } else { }) // {
            modules = selectedModules ++ [ configModule ];
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
    {
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
