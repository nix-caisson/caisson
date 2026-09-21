# SPDX-License-Identifier: MIT
{ lib, ... }:
{
  options.caisson.configInfo.configName = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      The canonical name of this configuration. Used in doc/version
      strings and as the default namespace name for the lib export.

      Some export options (`caisson.lib.export.enabled`) require this
      to be set. Enabling such an export without setting a name
      produces a clear error message.
    '';
  };
}
