# SPDX-License-Identifier: MIT
{ ... }:
{ self, ... }:
{
  systems = [ "x86_64-linux" ];

  # The default selector for `caisson.lib.exported` looks the namespace
  # the composition declares up in the composed library, so this alone
  # decides what the `lib` flake output carries.
  caisson.lib.export.enabled = true;

  perSystem =
    { pkgs, ... }:
    {
      checks.minimal-consumer-success =
        # The lib export picked the declared namespace, and nothing else
        # from the composed library came with it.
        assert self.lib.marker == "from-the-minimal-consumer-overlay";
        assert !(self.lib ? caisson);
        assert !(self.lib ? caisson-core);
        pkgs.runCommand "minimal-consumer-success" { } ''
          echo 'minimal consumer composed successfully' > $out
        '';
    };
}
