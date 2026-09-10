# SPDX-License-Identifier: MIT
{ ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "nixos";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "nixpkgs";
        context = "caisson.nixos";
        resolve = final.caisson-core.resolve;
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.manifest or { };
        };

      assertPkgSets =
        pkgSets:
        if pkgSets ? pkgs then
          pkgSets
        else
          throw "lib.caisson.nixos.mkConfiguration requires `pkgSets.pkgs` to be defined.";

      # eval-config evaluations carry the nixpkgs module, so the package
      # set lands on `nixpkgs.pkgs`; the minimal evaluator has no such
      # module, so there it is the `pkgs` module argument instead.
      mkFrameworkModule = pkgSets: {
        _file = "caisson-nixos:framework";
        config = {
          nixpkgs.pkgs = pkgSets.pkgs;
        };
      };
      mkMinimalFrameworkModule = pkgSets: {
        _file = "caisson-nixos:framework-minimal";
        config = {
          _module.args.pkgs = final.mkDefault pkgSets.pkgs;
        };
      };

      commonAccepted = [
        "ecosystemSrc"
        "pkgSets"
        "configModule"
        "moduleImports"
        "specialArgs"
      ];
      hints = {
        modules = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
        pkgs = "pass the package set as `pkgSets.pkgs`.";
        baseModules = "the base module list belongs to the variant: mkConfiguration and mkConfigurationFull evaluate with NixOS' module list, mkConfigurationMinimal without it.";
      };
      mkCheck =
        name: extra: open:
        import ../check-args.nix {
          context = "lib.caisson.nixos.${name}";
          accepted = commonAccepted ++ extra;
          inherit hints open;
        };

      # What every variant composes from the caisson arguments: the
      # selected class modules, the config module and the framework
      # module as `modules`, and pkgSets threaded through `specialArgs`
      # (framework defaults first; the caller's win on conflict, as is
      # normal in the Nix ecosystem).
      compose =
        {
          minimal ? false,
        }:
        {
          ecosystemSrc ? null,
          pkgSets,
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          ...
        }:
        let
          checkedPkgSets = assertPkgSets pkgSets;
          selectedModules = moduleImports (final.caisson-core.modules.nixos or { });
          frameworkModule =
            if minimal then mkMinimalFrameworkModule checkedPkgSets else mkFrameworkModule checkedPkgSets;
        in
        {
          src = resolveSrc ecosystemSrc;
          inherit checkedPkgSets;
          modules = selectedModules ++ [
            configModule
            frameworkModule
          ];
          specialArgs = {
            pkgSets = checkedPkgSets;
          }
          // specialArgs;
        };

      # eval-config evaluations. `system` defaults to the package set's
      # host platform.
      evalConfigArgs = args: common: {
        modules = common.modules;
        specialArgs = common.specialArgs;
        system =
          args.system or (common.checkedPkgSets.pkgs.stdenv.hostPlatform.system
            or (common.checkedPkgSets.pkgs.system or null)
          );
      };
      evalConfig = common: import "${common.src}/nixos/lib/eval-config.nix";

      mkConfiguration =
        rawArgs:
        let
          args = mkCheck "mkConfiguration" [
            "system"
          ] "lib.caisson.nixos.mkConfigurationWithEcosystemArgs" rawArgs;
          common = compose { } args;
        in
        evalConfig common (evalConfigArgs args common);

      # eval-config with nixpkgs' module list passed explicitly as
      # `baseModules`.
      mkConfigurationFull =
        rawArgs:
        let
          args = mkCheck "mkConfigurationFull" [
            "system"
          ] "lib.caisson.nixos.mkConfigurationWithEcosystemArgs" rawArgs;
          common = compose { } args;
        in
        evalConfig common (
          evalConfigArgs args common
          // {
            baseModules = import "${common.src}/nixos/modules/module-list.nix";
          }
        );

      # The same composition as mkConfiguration, then `ecosystemArgs`
      # merged over the eval-config call verbatim: everything
      # eval-config takes (system, pkgs, baseModules, specialArgs,
      # modules, modulesLocation, prefix, lib, extraModules) can be set
      # or replaced there.
      mkConfigurationWithEcosystemArgs =
        rawArgs:
        let
          args = mkCheck "mkConfigurationWithEcosystemArgs" [ "system" "ecosystemArgs" ] null rawArgs;
          common = compose { } args;
        in
        evalConfig common (evalConfigArgs args common // (args.ecosystemArgs or { }));

      # nixos/lib's evalModules: no NixOS base modules, so the config
      # module declares any options it uses; the package set arrives as
      # the `pkgs` module argument.
      evalMinimalArgs = args: common: {
        prefix = args.prefix or [ ];
        modules = common.modules;
        specialArgs = common.specialArgs;
      };
      evalMinimal = common: (import "${common.src}/nixos/lib" { }).evalModules;

      mkConfigurationMinimal =
        rawArgs:
        let
          args = mkCheck "mkConfigurationMinimal" [
            "prefix"
          ] "lib.caisson.nixos.mkConfigurationMinimalWithEcosystemArgs" rawArgs;
          common = compose { minimal = true; } args;
        in
        evalMinimal common (evalMinimalArgs args common);

      mkConfigurationMinimalWithEcosystemArgs =
        rawArgs:
        let
          args = mkCheck "mkConfigurationMinimalWithEcosystemArgs" [ "prefix" "ecosystemArgs" ] null rawArgs;
          common = compose { minimal = true; } args;
        in
        evalMinimal common (evalMinimalArgs args common // (args.ecosystemArgs or { }));
    in
    {
      caisson = (prev.caisson or { }) // {
        nixos = ((prev.caisson or { }).nixos or { }) // {
          inherit
            mkModule
            mkConfiguration
            mkConfigurationFull
            mkConfigurationMinimal
            mkConfigurationWithEcosystemArgs
            mkConfigurationMinimalWithEcosystemArgs
            ;
        };
      };
    };

}
