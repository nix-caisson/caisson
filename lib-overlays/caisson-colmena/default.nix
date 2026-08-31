# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkColmenaModule = final.caisson.mkModule "colmena";

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive then
          ecosystemSrc
        else
          throw "lib.caisson-colmena.mkColmenaHive requires `ecosystemSrc.lib.makeHive`.";

      mkCommonArgs =
        args@{
          modules ? [ ],
          moduleImports ? modules: modules,
          specialArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson.modules.colmena or { });
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

      mkColmenaHive =
        args@{
          ecosystemSrc,
          ...
        }:
        let
          checkedEcosystemSrc = assertColmenaEcosystemSrc ecosystemSrc;
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
      caisson-colmena = (prev.caisson-colmena or { }) // {
        inherit
          mkColmenaHive
          mkColmenaModule
          ;
      };
    };

}
