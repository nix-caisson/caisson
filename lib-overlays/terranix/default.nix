# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkTerranixModule = final.caisson.mkModule "terranix";

      assertTerranixEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? terranixConfiguration then
          ecosystemSrc
        else
          throw "lib.caisson.terranix.mkTerranixConfiguration requires `ecosystemSrc.lib.terranixConfiguration`.";

      mkCommonArgs =
        args@{
          modules ? [ ],
          moduleImports ? modules: modules,
          extraArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson.modules.terranix or { });
        in
        {
          modules = (builtins.attrValues selectedModules) ++ modules;
          # Framework defaults first; caller's extraArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          extraArgs = {
            inputs = closure-inputs;
          }
          // extraArgs;
        };

      mkTerranixConfiguration =
        args@{
          ecosystemSrc,
          ...
        }:
        let
          checkedEcosystemSrc = assertTerranixEcosystemSrc ecosystemSrc;
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
