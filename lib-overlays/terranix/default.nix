# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkTerranixModule = final.caisson-core.mkModule "terranix";

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
          throw "lib.caisson.terranix.mkTerranixConfiguration requires `ecosystemSrc.lib.terranixConfiguration`.";

      mkCommonArgs =
        args@{
          modules ? [ ],
          moduleImports ? builtins.attrValues,
          extraArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.terranix or { });
        in
        {
          modules = selectedModules ++ modules;
          # Framework defaults first; caller's extraArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          extraArgs = {
            inputs = closure-inputs;
          }
          // extraArgs;
        };

      mkTerranixConfiguration =
        args@{
          ecosystemSrc ? null,
          ...
        }:
        let
          checkedEcosystemSrc = assertTerranixEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.manifest or { };
          });
          common = mkCommonArgs args;
          passthroughArgs = builtins.removeAttrs args [
            "ecosystemSrc"
            "extraArgs"
            "moduleImports"
            "modules"
          ];
        in
        checkedEcosystemSrc.lib.terranixConfiguration (
          passthroughArgs
          // {
            inherit (common)
              extraArgs
              modules
              ;
          }
        );
    in
    {
      caisson = (prev.caisson or { }) // {
        terranix = ((prev.caisson or { }).terranix or { }) // {
          inherit
            mkTerranixConfiguration
            mkTerranixModule
            ;
        };
      };
    };

}
