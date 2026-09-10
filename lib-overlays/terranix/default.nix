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

      mkCommonArgs =
        args@{
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          ...
        }:
        let
          selectedModules = moduleImports (final.caisson-core.modules.terranix or { });
        in
        {
          modules = selectedModules ++ [ configModule ];
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem. terranix
          # calls these extraArgs; the caisson surface uses one name.
          extraArgs = {
            inputs = closure-inputs;
          }
          // specialArgs;
        };

      mkConfiguration =
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
            "configModule"
            "moduleImports"
            "specialArgs"
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
            mkConfiguration
            mkModule
            ;
        };
      };
    };

}
