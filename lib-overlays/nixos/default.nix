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

      composeNixos = import ./compose.nix { inherit final; };

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

      compose =
        {
          minimal ? false,
        }:
        args:
        composeNixos {
          context = "lib.caisson.nixos.mkConfiguration";
          inherit minimal;
        } args
        // {
          src = resolveSrc (args.ecosystemSrc or null);
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
