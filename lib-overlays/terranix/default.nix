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

      # terranix evaluates against a package set, `pkgs` or a set it
      # instantiates for `system`. The composed call carries `pkgs` from
      # `pkgSets.pkgs`; the twin may supply either in `ecosystemArgs`.
      evaluate =
        composed: callArgs:
        if !(callArgs ? pkgs || callArgs ? system) then
          throw "lib.caisson.terranix: terranixConfiguration needs a package set; pass `pkgSets.pkgs`, or `pkgs` or `system` in `ecosystemArgs`."
        else
          composed.src.lib.terranixConfiguration callArgs;

      evaluation = selection.mkEvaluation { inherit compose evaluate; };

      integration = selection.mkIntegration {
        name = "terranix";
        class = "terranix";
        # `compose` destructures `configModule` without a default and
        # supplies the value of every optional argument left out.
        # `pkgSets` is optional here: the evaluator step accepts a
        # package set from `ecosystemArgs` instead, and reports the
        # miss when neither arrives.
        mkConfiguration =
          {
            # The configuration's module. Further modules of the class
            # are selected with `moduleImports`, from the registry.
            configModule,
            # The package sets; `pkgSets.pkgs` is the `pkgs` terranix
            # evaluates against, in place of `system`.
            pkgSets ? null,
            # The terranix flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the terranix class of the registry;
            # every entry named `default` when absent.
            moduleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies; terranix names these `extraArgs`.
            specialArgs ? null,
          }@args:
          evaluation args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule,
            pkgSets ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          evaluation args;
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        terranix = integration.namespace;
      };
    };

}
