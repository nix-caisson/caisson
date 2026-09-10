# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson-core.mkModule "colmena";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "colmena";
        context = "caisson.colmena";
        resolve = final.caisson-core.resolve;
      };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive then
          ecosystemSrc
        else
          throw "lib.caisson.colmena.mkConfiguration requires `ecosystemSrc.lib.makeHive`.";

      accepted = [
        "ecosystemSrc"
        "configModule"
        "moduleImports"
        "specialArgs"
        "pkgSets"
        "meta"
        "nodes"
      ];
      hints = {
        modules = "pass the hive-wide module as `configModule`; registered class modules are selected with `moduleImports`.";
        defaults = "pass the hive-wide module as `configModule`.";
        network = "pass hive metadata as `meta`.";
      };
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.colmena.mkConfigurationUnsupervised";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfigurationUnsupervised";
        accepted = accepted ++ [ "evaluatorArgs" ];
        inherit hints;
      };

      # The hive makeHive receives, composed from the caisson arguments:
      # the selected class modules and the config module become
      # `defaults`, framework special arguments merge into
      # `meta.specialArgs` (the caller's win on conflict, as is normal
      # in the Nix ecosystem), and pkgSets.pkgs is the default
      # `meta.nixpkgs`.
      compose =
        {
          ecosystemSrc ? null,
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          pkgSets ? null,
          meta ? { },
          nodes ? { },
          ...
        }:
        let
          checkedEcosystemSrc = assertColmenaEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.manifest or { };
          });
          selectedModules = moduleImports (final.caisson-core.modules.colmena or { });
        in
        {
          inherit checkedEcosystemSrc;
          hive = nodes // {
            meta =
              (if pkgSets != null && pkgSets ? pkgs then { nixpkgs = pkgSets.pkgs; } else { })
              // meta
              // {
                specialArgs = {
                  inputs = closure-inputs;
                }
                // (if pkgSets != null then { inherit pkgSets; } else { })
                // (meta.specialArgs or { })
                // specialArgs;
              };
            defaults =
              { ... }:
              {
                imports = selectedModules ++ [ configModule ];
              };
          };
        };

      mkConfiguration =
        rawArgs:
        let
          composed = compose (checkArgs rawArgs);
        in
        composed.checkedEcosystemSrc.lib.makeHive composed.hive;

      # The same composition, then `evaluatorArgs` merged over the hive
      # verbatim: every attribute makeHive reads (meta, defaults, the
      # nodes) can be set or replaced there.
      mkConfigurationUnsupervised =
        rawArgs:
        let
          args = checkOpenArgs rawArgs;
          composed = compose args;
        in
        composed.checkedEcosystemSrc.lib.makeHive (composed.hive // (args.evaluatorArgs or { }));
    in
    {
      caisson = (prev.caisson or { }) // {
        colmena = ((prev.caisson or { }).colmena or { }) // {
          inherit
            mkConfiguration
            mkConfigurationUnsupervised
            mkModule
            ;
        };
      };
    };

}
