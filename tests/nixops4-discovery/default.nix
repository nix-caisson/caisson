# SPDX-License-Identifier: MIT
#
# The discovery program of a NixOps4 root, built and run. `inputs` is
# the dependency pool of the checks partition with `caisson` set to
# the tree itself.
#
# Each deployment below holds resources that record their outputs in a
# state resource. Its root composite takes NixOps4 from a source whose
# `nixops4` package is a stand-in: `nixops4 state dump <path>` prints
# the dump recorded in this directory for the state resource at that
# path. The dumps are trimmed from the dumps of a real `nixops4 apply`.
# Building the program runs shellcheck on it. Running it must print the
# output values at the paths the root names in `argsNeeded`, with the
# values the dumps record.
{ inputs }:
let
  suite = import ../pinned-world { inherit inputs; };
  inherit (suite.fixtures)
    hiveLib
    pkgs
    nixops4ArgPathsOf
    nixops4Entry
    ;
  system = "x86_64-linux";
  local = inputs.nixops4.modules.nixops4Provider.local;

  # The stand-in for NixOps4: it answers `state dump <path>` with the
  # dump recorded for the state resource at that path.
  nixops4 = pkgs.writeShellScriptBin "nixops4" ''
    case "''${*: -1}" in
      state) cat ${./root-state.json} ;;
      group.gstate) cat ${./group-state.json} ;;
      *) echo "no dump for ''${*: -1}" >&2; exit 1 ;;
    esac
  '';
  ecosystemSrc = inputs.nixops4 // {
    packages = inputs.nixops4.packages // {
      ${system} = inputs.nixops4.packages.${system} // {
        inherit nixops4;
      };
    };
  };

  # A top whose root composite `nixops4` holds the composite `group`,
  # with the state resource `gstate` and the resource `inner`, which
  # records its outputs there. With `rootState`, the root also holds the
  # state resource `state` and the resource `a`, which records its
  # outputs there.
  topWith =
    { rootState }:
    hiveLib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        let
          resource =
            module:
            lib.caisson.caisson-nixops4-resource.mkConfiguration {
              configModule =
                { providers, ... }:
                {
                  imports = [ module ];
                  providers.local = local;
                };
            };
          stateFile =
            name:
            resource (
              { providers, ... }:
              {
                type = providers.local.state_file;
                inputs.name = name;
              }
            );
          exec =
            state:
            resource (
              { providers, ... }:
              {
                type = providers.local.exec;
                inputs.executable = "/bin/sh";
                inherit state;
              }
            );
        in
        {
          caisson.caisson-nixops4-composite.configurations.nixops4 =
            lib.caisson.caisson-nixops4-composite.mkConfiguration
              {
                ecosystemSrc = _sources: ecosystemSrc;
                configModule =
                  { lib, members, ... }:
                  {
                    caisson.caisson-nixops4-composite.configurations.group =
                      lib.caisson.caisson-nixops4-composite.mkConfiguration
                        {
                          configModule =
                            { members, ... }:
                            {
                              caisson.caisson-nixops4-resource.configurations = {
                                gstate = stateFile "group-state.json";
                                inner = exec members.gstate;
                              };
                            };
                        };
                    caisson.caisson-nixops4-resource.configurations = lib.optionalAttrs rootState {
                      state = stateFile "state.json";
                      a = exec members.state;
                    };
                  };
              };
        };
    };

  # The paths of the values in a tree of attribute sets, each a list of
  # names.
  valuePathsOf =
    let
      walk =
        path: value:
        if builtins.isAttrs value then
          builtins.concatMap (name: walk (path ++ [ name ]) value.${name}) (builtins.attrNames value)
        else
          [ path ];
    in
    walk [ ];

  # The discovery program of a top's root and the output values it must
  # print. The values are those the dumps record, and their paths are
  # the paths of the outputs the root names in `argsNeeded`.
  caseOf =
    name: rootState: outputValues:
    let
      root =
        (nixops4Entry (topWith {
          inherit rootState;
        })).finalize
          {
            args.resourceProviderSystem = system;
            argsSource = _: "the discovery check";
          };
      expected = {
        inherit outputValues;
        resourceProviderSystem = system;
      };
    in
    assert nixops4ArgPathsOf root.argsNeeded.outputValues == valuePathsOf outputValues;
    {
      inherit name;
      program = root.discoverArgs { inherit system; };
      expected = pkgs.writeText "${name}.json" (builtins.toJSON expected);
    };

  cases = [
    # One state resource, inside a composite.
    (caseOf "nested" false { group.inner.stdout = "nested-state-value"; })
    # Two state resources, one at the root and one inside a composite.
    (caseOf "both" true {
      a.stdout = "alpha-42";
      group.inner.stdout = "nested-state-value";
    })
  ];
in
pkgs.runCommand "nixops4-discovery" { nativeBuildInputs = [ pkgs.jq ]; } (
  pkgs.lib.concatMapStrings (case: ''
    ${pkgs.lib.getExe case.program} > ${case.name}.json
    jq -S . ${case.expected} > ${case.name}.expected
    jq -S . ${case.name}.json > ${case.name}.printed
    diff -u ${case.name}.expected ${case.name}.printed
  '') cases
  + ''
    touch $out
  ''
)
