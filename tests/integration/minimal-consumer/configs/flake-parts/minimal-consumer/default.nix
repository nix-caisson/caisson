# SPDX-License-Identifier: MIT
{ ... }:
{ self, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, ... }:
    {
      checks.minimal-consumer-success =
        # The `lib` flake output is the composed library. The overlay
        # of this flake is in it under the declared name, and so is
        # the manifest of the flake, which a flake that lists this
        # flake in `projects` reads.
        assert self.lib.minimal-consumer.marker == "from-the-minimal-consumer-overlay";
        assert self.lib.caisson-core.evalManifest._type == "caisson-manifest";
        assert self.lib.caisson-core.evalManifest.outputs ? exports;
        pkgs.runCommand "minimal-consumer-success" { } ''
          echo 'minimal consumer composed successfully' > $out
        '';
    };
}
