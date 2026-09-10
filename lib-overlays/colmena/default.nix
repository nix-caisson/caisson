# SPDX-License-Identifier: MIT
#
# The colmena integration. A hive's nodes are NixOS configurations, so
# the integration composes them exactly as lib.caisson.nixos does (the
# shared composition in ../nixos/compose.nix): the selected nixos-class
# modules, the hive-wide config module and the framework's package-set
# module become the hive's `defaults`, and each node adds its own
# config module and deployment settings. A node's toplevel is therefore
# the same derivation lib.caisson.nixos.mkConfiguration builds from the
# same modules; there is no colmena module class.
{ ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
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

      composeNixos = import ../nixos/compose.nix { inherit final; };

      accepted = [
        "ecosystemSrc"
        "pkgSets"
        "configModule"
        "moduleImports"
        "specialArgs"
        "meta"
        "nodes"
      ];
      hints = {
        modules = "pass the hive-wide module as `configModule`; registered nixos-class modules are selected with `moduleImports`.";
        defaults = "pass the hive-wide module as `configModule`.";
        network = "pass hive metadata as `meta`.";
      };
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.colmena.mkConfigurationWithEcosystemArgs";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfigurationWithEcosystemArgs";
        accepted = accepted ++ [ "ecosystemArgs" ];
        inherit hints;
      };

      # The parts of colmena's `meta` the integration composes itself.
      metaHints = {
        nixpkgs = "pass the nodes' package set as `pkgSets.pkgs`.";
        nodeNixpkgs = "every node evaluates against `pkgSets.pkgs`; a per-node package set is an ecosystem argument (mkConfigurationWithEcosystemArgs).";
        specialArgs = "pass extra module arguments as `specialArgs`.";
        nodeSpecialArgs = "per-node module arguments are an ecosystem argument (mkConfigurationWithEcosystemArgs).";
      };
      checkMeta =
        meta:
        let
          offending = builtins.filter (name: builtins.hasAttr name meta) (builtins.attrNames metaHints);
        in
        if offending == [ ] then
          meta
        else
          throw "lib.caisson.colmena.mkConfiguration does not accept `meta.${builtins.head offending}`: ${
            metaHints.${builtins.head offending}
          }";

      mkNode =
        name: node:
        if !(builtins.isAttrs node && node ? configModule) then
          throw "lib.caisson.colmena.mkConfiguration requires `nodes.${name}.configModule`."
        else
          {
            _file = "caisson-colmena:node-${name}";
            imports = [
              node.configModule
            ]
            ++ (if node ? deployment then [ { inherit (node) deployment; } ] else [ ]);
          };

      compose =
        {
          ecosystemSrc ? null,
          pkgSets,
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          meta ? { },
          nodes ? { },
          ...
        }:
        let
          checkedEcosystemSrc = assertColmenaEcosystemSrc (resolveEcosystemSrc {
            explicit = ecosystemSrc;
            manifest = final.caisson-core.manifest or { };
          });
          nixos = composeNixos { context = "lib.caisson.colmena.mkConfiguration"; } {
            inherit
              pkgSets
              configModule
              moduleImports
              specialArgs
              ;
          };
          pkgs = nixos.checkedPkgSets.pkgs;
        in
        {
          inherit checkedEcosystemSrc;
          hive = builtins.mapAttrs mkNode nodes // {
            meta = checkMeta meta // {
              # colmena wants an initialized nixpkgs it reads `path`,
              # `lib` and `stdenv.hostPlatform.system` from, and it
              # seeds every node's `nixpkgs.overlays` and
              # `nixpkgs.config` from the instance's own. The nodes take
              # the package set the way every caisson NixOS evaluation
              # does, through the framework's `nixpkgs.pkgs`, which
              # nixpkgs allows only beside empty seeding; so colmena is
              # handed the package set's identity with nothing to seed,
              # and the nodes' nixpkgs module resolves to the very
              # instance.
              nixpkgs = {
                inherit (pkgs) path lib stdenv;
                overlays = [ ];
                config = { };
              };
              inherit (nixos) specialArgs;
            };
            defaults =
              { ... }:
              {
                _file = "caisson-colmena:defaults";
                imports = nixos.modules;
              };
          };
        };

      mkConfiguration =
        rawArgs:
        let
          composed = compose (checkArgs rawArgs);
        in
        composed.checkedEcosystemSrc.lib.makeHive composed.hive;

      # The same composition, then `ecosystemArgs` merged over the hive
      # verbatim: every attribute makeHive reads (meta, defaults, the
      # nodes) can be set or replaced there.
      mkConfigurationWithEcosystemArgs =
        rawArgs:
        let
          args = checkOpenArgs rawArgs;
          composed = compose args;
        in
        composed.checkedEcosystemSrc.lib.makeHive (composed.hive // (args.ecosystemArgs or { }));
    in
    {
      caisson = (prev.caisson or { }) // {
        colmena = ((prev.caisson or { }).colmena or { }) // {
          inherit
            mkConfiguration
            mkConfigurationWithEcosystemArgs
            ;
        };
      };
    };

}
