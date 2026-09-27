# SPDX-License-Identifier: MIT
#
# The terranix integration: it owns the `terranix` class and
# evaluates it with `terranixConfiguration` from the terranix flake.
{
  closure-inputs,
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
      selection = final.caisson.integrations;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "terranix";
        context = "caisson.terranix";
      };

      assertTerranixEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? terranixConfiguration then
          ecosystemSrc
        else
          throw "lib.caisson.terranix requires `ecosystemSrc.lib.terranixConfiguration`.";

      # terranixConfiguration's arguments, composed from the caisson
      # arguments: pkgSets.pkgs is `pkgs`, the selected class modules
      # and the config module are `modules`, and specialArgs becomes
      # terranix's `extraArgs` (framework defaults first; the values the
      # caller passed win on conflict).
      compose =
        {
          ecosystemSrc ? null,
          configModule,
          moduleImports ? selection.defaultModuleImports,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          src = assertTerranixEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.libManifest or { };
          });
          registry = final.caisson-core.modules.terranix or { };
          # The framework module of the class: every registered `core`, forced.
          coreModules = selection.coreModules registry;
          selectedModules = moduleImports registry;
        in
        {
          inherit src;
          ecosystemArgs = (if pkgSets != null && pkgSets ? pkgs then { pkgs = pkgSets.pkgs; } else { }) // {
            modules = coreModules ++ selectedModules ++ [ configModule ];
            extraArgs = {
              inputs = closure-inputs;
            }
            // (if pkgSets != null then { inherit pkgSets; } else { })
            // specialArgs;
          };
        };

      # terranix evaluates against a package set, `pkgs` or one it
      # instantiates for `system`. The composed call carries `pkgs` from
      # `pkgSets.pkgs`; the twin may supply either in `ecosystemArgs`.
      evaluate =
        composed: callArgs:
        if !(callArgs ? pkgs || callArgs ? system) then
          throw "lib.caisson.terranix: terranixConfiguration needs a package set; pass `pkgSets.pkgs`, or `pkgs` or `system` in `ecosystemArgs`."
        else
          composed.src.lib.terranixConfiguration callArgs;

      integration = selection.mkIntegration {
        name = "terranix";
        class = "terranix";
        # `pkgSets` defaults to null here: the evaluator step accepts a
        # package set from `ecosystemArgs` instead, and reports the
        # miss when neither arrives.
        required = [ "configModule" ];
        hints = {
          extraArgs = "pass extra module arguments as `specialArgs`.";
          pkgs = "pass the package set as `pkgSets.pkgs`.";
          system = "pass the package set as `pkgSets.pkgs`; terranix evaluates against it.";
        };
        inherit compose evaluate;
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        terranix = integration.namespace;
      };
    };

}
