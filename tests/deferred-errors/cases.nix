# SPDX-License-Identifier: MIT
#
# The cases of tests/deferred-errors/check.sh: deferred configurations
# that fail, each with a line of the message it must fail with. `lib`
# is caisson's composed library, and `nixops4` the NixOps4 source,
# whose component modules the NixOps4 integrations evaluate. The
# deployments use a provider written here, `probe`, whose resource
# type `exec` has the output `stdout`, so nothing of NixOps4's flake
# outputs is evaluated.
#
# Each case is `{ value; message; }`: forcing `value` must fail, and the
# error must contain `message` as written.
{ lib, nixops4 }:
let
  system = "x86_64-linux";

  # The NixOps4 source as the integrations check it: its component
  # modules, and a module collection that holds `nixops4Provider`.
  ecosystemSrc = {
    outPath = nixops4;
    modules.nixops4Provider = { };
  };

  provider =
    { lib, ... }:
    {
      executable = "/bin/probe";
      resourceTypes.exec = {
        description = "A resource with the output `stdout`.";
        requireState = false;
        inputs.options.value = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        outputs.options.stdout = lib.mkOption { type = lib.types.str; };
      };
    };

  # A native composite with the module `module`.
  composite =
    lib: module:
    lib.caisson.caisson-nixops4-composite.mkConfiguration {
      ecosystemSrc = _sources: ecosystemSrc;
      configModule = module;
    };

  # A native resource of the type `exec` with the module `module`.
  resource =
    lib: module:
    lib.caisson.caisson-nixops4-resource.mkConfiguration {
      ecosystemSrc = _sources: ecosystemSrc;
      configModule =
        { providers, ... }:
        {
          imports = [ module ];
          providers.probe = provider;
          type = providers.probe.exec;
        };
    };

  # A top whose root composite `nixops4` has the module `module`.
  topWith =
    module:
    lib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.caisson-nixops4-composite.configurations.nixops4 = composite lib module;
        };
    };

  # A top whose root is an upstream-compatible nixops4 configuration
  # made from `modules`.
  upstreamTopWith =
    modules:
    lib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.nixops4.configurations.nixops4 = lib.caisson.nixops4.mkConfiguration {
            ecosystemSrc = _sources: ecosystemSrc;
            inherit modules;
          };
        };
    };

  # The root of a top, finalized with the deploying system alone, as
  # `getProviders` finalizes it: every output fails when it is read.
  rootOf =
    top:
    let
      children = top.caisson.manifest.children;
    in
    (children.caisson-nixops4-composite or children.nixops4).nixops4.finalize {
      args.resourceProviderSystem = system;
      argsSource = _: "the check";
    };

  # A composite module whose resource `reader` reads the output
  # `stdout` of its member `source`.
  readerModule =
    { lib, members, ... }:
    {
      caisson.caisson-nixops4-resource.configurations = {
        source = resource lib { };
        reader = resource lib { inputs.value = members.source.outputs.stdout; };
      };
    };
in
{
  # An output NixOps4 has not passed names its member path from the
  # root.
  missingOutput = {
    value = (rootOf (topWith readerModule)).outputs.export;
    message = "caisson-deferred: needs outputValues.source.stdout";
  };

  # The member path of an output inside nested composites holds each
  # composite.
  missingNestedOutput = {
    value =
      (rootOf (
        topWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.a = composite lib (
              { lib, ... }:
              {
                caisson.caisson-nixops4-composite.configurations.b = composite lib readerModule;
              }
            );
          }
        )
      )).outputs.export;
    message = "caisson-deferred: needs outputValues.a.b.source.stdout";
  };

  # The same holds for an upstream composite inside another.
  missingUpstreamNestedOutput = {
    value =
      (rootOf (upstreamTopWith [
        (
          { providers, members, ... }:
          {
            providers.probe = provider;
            members.g.members.h.members.source.type = providers.probe.exec;
            members.g.members.reader = {
              type = providers.probe.exec;
              inputs.value = members.g.members.h.members.source.outputs.stdout;
            };
          }
        )
      ])).outputs.export;
    message = "caisson-deferred: needs outputValues.g.h.source.stdout";
  };

  # Which members a composite has may not depend on their outputs.
  membersFromOutputs = {
    value =
      (rootOf (
        topWith (
          { lib, members, ... }:
          {
            caisson.caisson-nixops4-resource.configurations = {
              source = resource lib { };
            }
            // lib.optionalAttrs (members.source.outputs.stdout == "more") {
              extra = resource lib { };
            };
          }
        )
      )).argsNeeded;
    message = "the composite at the root reads its members, or their";
  };

  # The error names the composite that reads them, here one beneath the
  # root.
  nestedMembersFromOutputs = {
    value =
      (rootOf (
        topWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.a = composite lib (
              { lib, members, ... }:
              {
                caisson.caisson-nixops4-resource.configurations = lib.optionalAttrs (members ? source) {
                  source = resource lib { };
                };
              }
            );
          }
        )
      )).argsNeeded;
    message = "the composite at a reads its members, or their";
  };

  # Whether an upstream member is a composite or a resource may not
  # depend on the outputs of another member.
  upstreamKindFromOutputs = {
    value =
      (rootOf (upstreamTopWith [
        (
          { providers, members, ... }:
          {
            providers.probe = provider;
            members.source.type = providers.probe.exec;
            members.dynamic =
              if members.source.outputs.stdout == "resource" then
                { type = providers.probe.exec; }
              else
                { members.inner.type = providers.probe.exec; };
          }
        )
      ])).argsNeeded;
    message = "the composite at the root reads its members, or their";
  };

  # A resource may not name its outputs from its own outputs.
  skeletonFromOwnOutputs = {
    value =
      (rootOf (
        topWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-resource.configurations.selfish = resource lib (
              { config, ... }:
              {
                outputsSkeleton = lib.mkForce (
                  {
                    stdout = { };
                  }
                  // lib.optionalAttrs (config.outputs.stdout == "more") { extra = { }; }
                );
              }
            );
          }
        )
      )).argsNeeded;
    message = "the resource at selfish reads its own outputs in its";
  };

  # A member is a composite or a resource.
  compositeAndResource = {
    value =
      (rootOf (
        topWith (
          { lib, ... }:
          {
            caisson.caisson-nixops4-resource.configurations.x = resource lib { };
            caisson.caisson-nixops4-composite.configurations.x = composite lib { };
          }
        )
      )).argsNeeded;
    message = "`x` both as a composite and as a";
  };

  # A flake publishes one root as `nixops4`.
  twoRoots = {
    value =
      (lib.caisson.structural.mkTopConfiguration {
        moduleImports = _modules: [ ];
        configModule =
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.nixops4 = composite lib { };
            caisson.nixops4.configurations.nixops4 = lib.caisson.nixops4.mkConfiguration {
              ecosystemSrc = _sources: ecosystemSrc;
            };
          };
      }).nixops4;
    message = "nixops4: this output holds a single value, the configuration";
  };

  # A root is declared under the name of the output it fills.
  rootNamedOtherwise = {
    value =
      (lib.caisson.structural.mkTopConfiguration {
        moduleImports = _modules: [ ];
        configModule =
          { lib, ... }:
          {
            caisson.caisson-nixops4-composite.configurations.deploy = composite lib { };
          };
      }).nixops4;
    message = "caisson-nixops4-composite deploy";
  };
}
