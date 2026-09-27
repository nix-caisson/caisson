# SPDX-License-Identifier: MIT
{ config, lib, ... }:
{

  options.caisson.lib = {

    export.enabled = lib.mkEnableOption "lib export";

    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
      description = ''
        Function that selects which parts of the composed library to
        publish as the `lib` export. Receives the composed library;
        defaults to the namespace that library's composition declares
        (`namespace` on mkLib, carried in the manifest).
      '';
      default =
        composedLib:
        let
          namespace = composedLib.caisson-core.libManifest.namespace or null;
        in
        assert lib.assertMsg (namespace != null)
          "caisson.lib.export.enabled is true but this composition declares no namespace, so there is no library namespace to publish. Declare `namespace` in the mkLib call, select the parts to publish with caisson.lib.exported, or disable lib export.";
        composedLib.${namespace};
      defaultText = "composedLib: composedLib.\${the namespace the composition declares}";
    };

  };

  config = {
    caisson.lib.export.enabled = lib.mkDefault false;

    caisson.exports.lib =
      if config.caisson.lib.export.enabled then config.caisson.lib.exported lib else { };
  };
}
