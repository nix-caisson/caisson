# SPDX-License-Identifier: MIT
{
  contributeClasses,
  entries,
  mkLibOverlay,
  ...
}:
{

  imports = [
    entries.nixpkgs-lib
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "nixos";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixpkgs";
        context = "caisson.nixos";
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.libManifest or { };
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
        baseModules = "the base module list belongs to the entry point: mkConfiguration and mkConfigurationFull evaluate with NixOS' module list, lib.caisson.nixos-minimal.mkConfiguration without it.";
      };
      mkCheck =
        name: extra: open:
        final.caisson.integrations.checkArgs {
          context = "lib.caisson.nixos.${name}";
          accepted = commonAccepted ++ extra;
          inherit hints open;
        };

      # The composition of the class: the module list, the special
      # arguments and the resolved nixpkgs source, from the caisson
      # arguments. Every entry point here builds on it, and so does an
      # integration that evaluates the nixos class with another
      # evaluator (nixos-minimal), through `lib.caisson.nixos.compose`.
      compose =
        {
          context ? "lib.caisson.nixos.mkConfiguration",
          # Whether the evaluation carries NixOS' nixpkgs module, so
          # the package set lands on `nixpkgs.pkgs`; without it, the
          # set is the `pkgs` module argument.
          nixpkgsModule ? true,
        }:
        args:
        composeNixos { inherit context nixpkgsModule; } args
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
    in
    # This integration owns the `nixos` class.
    contributeClasses prev {
      nixos = {
        integration = "nixos";
        inherit mkModule;
      };
    }
    // {
      caisson = (prev.caisson or { }) // {
        nixos = ((prev.caisson or { }).nixos or { }) // {
          inherit
            compose
            mkModule
            mkConfiguration
            mkConfigurationFull
            mkConfigurationWithEcosystemArgs
            ;
        };
      };
    };

}
