# SPDX-License-Identifier: MIT
#
# The configuration's name. Having one is a consequence of position in
# the composition tree: a parent confers a name by declaring a child
# under an attribute, and a configuration no parent declares takes the
# one name it does hold, the namespace its composition contributes to
# the composed library (`namespace` on mkLib, carried in the manifest).
# A composition that declares no namespace leaves such a configuration
# unnamed.
{ config, lib, ... }:
let
  # A manifest from a caisson-core that predates the field carries none,
  # which reads the same as a composition that declares no namespace.
  namespace = config.caisson.manifest.namespace or null;
in
{
  options.caisson.configInfo.configName = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      The canonical name of this configuration. Used in doc/version
      strings and as the default namespace name for the lib export.

      Defaults to the namespace the composition declares on mkLib,
      which is the name a configuration no parent declares holds.

      Some export options (`caisson.lib.export.enabled`) require this
      to be set. Enabling such an export in a composition that declares
      no namespace, without setting a name, produces a clear error
      message.
    '';
  };

  config.caisson.configInfo.configName = lib.mkIf (namespace != null) (lib.mkDefault namespace);
}
