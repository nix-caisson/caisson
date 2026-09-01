# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkColmenaModule = final.caisson-core.mkModule "colmena";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "colmena";
        context = "caisson.colmena";
      };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive then
          ecosystemSrc
        else
          throw "lib.caisson.colmena.mkColmenaHive requires `ecosystemSrc.lib.makeHive`.";

      mkCommonArgs =
        args@{
          modules ? [ ],
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.colmena or { });
        in
        {
          modules = selectedModules ++ modules;
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          specialArgs = {
            inputs = closure-inputs;
          }
          // specialArgs;
        };

      mkColmenaHive =
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
            "modules"
            "moduleImports"
            "specialArgs"
          ];
          baseMeta = passthroughArgs.meta or { };
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
            mkColmenaHive
            mkColmenaModule
            ;
        };
      };
    };

}
