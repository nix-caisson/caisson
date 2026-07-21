# SPDX-License-Identifier: MIT
{ ... }:
{ lib, ... }:
{
  options = {
    caisson.configInfo.configName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The canonical name of this flake. Used in doc/version strings and as
        a default namespace name for exports.

        Some export options (e.g. `caisson.lib.export.enabled`) require this
        to be set. Enabling such an export without setting a name will produce
        a clear error message.
      '';
    };
  };
}
