# SPDX-License-Identifier: MIT
#
# The integrations' ecosystem-source resolution: caisson-core's
# layered `resolve` (the explicit argument, then the composition's
# declared `ecosystems.<name>`, then an input with exactly the
# declared name), with the miss interpreted here, where the
# integration knows what to say; the resolver itself can never format
# a message, because a miss is the plain value null. The declarations
# and inputs are the serving composition's
# mkLib-time facts, read from its manifest; a manifest-less
# composition (composed without mkLib) has only the explicit channel.
let
  caisson-core = import ../vendor/caisson-core/lib;
in
{
  # the integration's name for its target ecosystem, e.g. "nixpkgs"
  name,
  # names the caller in the miss message, e.g. "caisson.nixos"
  context,
}:
{
  explicit ? null,
  # the serving composition's caisson-core.manifest, or { }
  manifest ? { },
}:
let
  resolved = caisson-core.resolve {
    inherit name explicit;
    defaults = manifest.ecosystems or { };
    inputs = manifest.inputs or { };
  };
in
if resolved != null then
  resolved
else
  throw ''
    ${context}: no ${name} ecosystem source. Pass `ecosystemSrc`
    explicitly, declare `ecosystems.${name}` in the composition's
    mkLib call, or give the composing flake an input named exactly
    `${name}`.
  ''
