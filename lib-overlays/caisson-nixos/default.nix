# SPDX-License-Identifier: MIT
{ ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkNixosModule = final.caisson.mkModule "nixos";

      assertPkgSets =
        pkgSets:
        if pkgSets ? pkgs then
          pkgSets
        else
          throw "lib.caisson-nixos.mkSystem requires `pkgSets.pkgs` to be defined.";

      mkFrameworkModule = pkgSets: {
        _file = "caisson-nixos:framework";
        config = {
          nixpkgs.pkgs = pkgSets.pkgs;
        };
      };

      mkCommonArgs =
        args@{
          pkgSets,
          configModule,
          moduleImports ? modules: modules,
          specialArgs ? { },
          ...
        }:
        let
          checkedPkgSets = assertPkgSets pkgSets;
          resolvedSystem =
            args.system
              or (checkedPkgSets.pkgs.stdenv.hostPlatform.system or (checkedPkgSets.pkgs.system or null));
          selectedModules = moduleImports (final.caisson.modules.nixos or { });
          extraModules = builtins.attrValues selectedModules;
          frameworkModule = mkFrameworkModule checkedPkgSets;
        in
        {
          inherit checkedPkgSets;
          system = resolvedSystem;
          modules = extraModules ++ [
            configModule
            frameworkModule
          ];
          # Framework defaults first; caller's specialArgs wins on conflict.
          # This is intentional and normal in the Nix ecosystem.
          specialArgs = {
            pkgSets = checkedPkgSets;
          }
          // specialArgs;
        };

      mkSystem =
        args@{
          ecosystemSrc,
          ...
        }:
        let
          common = mkCommonArgs args;
          passthroughArgs = builtins.removeAttrs args [
            "ecosystemSrc"
            "pkgSets"
            "configModule"
            "moduleImports"
            "specialArgs"
          ];
          evalConfig = import "${ecosystemSrc}/nixos/lib/eval-config.nix";
        in
        evalConfig (
          passthroughArgs
          // {
            modules = common.modules;
            specialArgs = common.specialArgs;
            system = common.system;
          }
        );

      mkSystemFull =
        args@{
          ecosystemSrc,
          ...
        }:
        let
          common = mkCommonArgs args;
          passthroughArgs = builtins.removeAttrs args [
            "ecosystemSrc"
            "pkgSets"
            "configModule"
            "moduleImports"
            "specialArgs"
          ];
          evalConfig = import "${ecosystemSrc}/nixos/lib/eval-config.nix";
        in
        evalConfig (
          passthroughArgs
          // {
            baseModules = import "${ecosystemSrc}/nixos/modules/module-list.nix";
            modules = common.modules;
            specialArgs = common.specialArgs;
            system = common.system;
          }
        );

      mkSystemMinimal =
        args@{
          ecosystemSrc,
          prefix ? [ ],
          ...
        }:
        let
          common = mkCommonArgs args;
          nixosLib = import "${ecosystemSrc}/nixos/lib" { };
        in
        nixosLib.evalModules {
          inherit prefix;
          modules = common.modules;
          specialArgs = common.specialArgs;
        };
    in
    {
      caisson-nixos = (prev.caisson-nixos or { }) // {
        inherit
          mkNixosModule
          mkSystem
          mkSystemMinimal
          mkSystemFull
          ;
      };
    };

}
