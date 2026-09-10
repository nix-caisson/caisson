# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "colmena";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "colmena";
        context = "caisson.colmena";
        resolve = final.caisson-core.resolve;
      };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive then
          ecosystemSrc
        else
          throw "lib.caisson.colmena.mkConfiguration requires `ecosystemSrc.lib.makeHive`.";

      mkCommonArgs =
        args@{
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.colmena or { });
        in
        {
          modules = selectedModules ++ [ configModule ];
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          specialArgs = {
            inputs = closure-inputs;
          }
          // (if pkgSets != null then { inherit pkgSets; } else { })
          // specialArgs;
          inherit pkgSets;
        };

      mkConfiguration =
        args@{
          ecosystemSrc ? null,
          ...
        }:
        let
          checkedEcosystemSrc = assertColmenaEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.manifest or { };
          });
          common = mkCommonArgs args;
          passthroughArgs = builtins.removeAttrs args [
            "ecosystemSrc"
            "configModule"
            "moduleImports"
            "specialArgs"
            "pkgSets"
          ];
          # The hive's package set is meta.nixpkgs; pkgSets.pkgs is its
          # default, an explicit meta.nixpkgs wins.
          baseMeta =
            (
              if common.pkgSets != null && common.pkgSets ? pkgs then { nixpkgs = common.pkgSets.pkgs; } else { }
            )
            // (passthroughArgs.meta or { });
          baseDefaults = passthroughArgs.defaults or { };
        in
        checkedEcosystemSrc.lib.makeHive (
          passthroughArgs
          // {
            meta = baseMeta // {
              specialArgs = (baseMeta.specialArgs or { }) // common.specialArgs;
            };
            defaults =
              { ... }:
              {
                imports = common.modules ++ [ baseDefaults ];
              };
          }
        );
    in
    {
      caisson = (prev.caisson or { }) // {
        colmena = ((prev.caisson or { }).colmena or { }) // {
          inherit
            mkConfiguration
            mkModule
            ;
        };
      };
    };

}
