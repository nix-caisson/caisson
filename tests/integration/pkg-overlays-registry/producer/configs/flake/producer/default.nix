# SPDX-License-Identifier: MIT
#
# The producer's flake: its package set applies its own default entry,
# and its exports hold what it registers itself and nothing caisson
# contributed through `projects`.
{ ... }:
{
  inputs,
  lib,
  self,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  caisson.nixpkgs.pkgSets.pkgs.pkgFunction = import inputs.nixpkgs;

  perSystem =
    { pkgs, system, ... }:
    {
      checks.pkg-overlays-registry-producer =
        let
          # A consumer that is not caisson: the plain overlay carries the
          # entries its entry imports.
          plain = import inputs.nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        # The default selection: the default entry and its import, once.
        assert pkgs.producerDefault == "ok";
        assert pkgs.sharedApplied == 1;
        assert !(pkgs ? producerExtra);
        # The registry is exported as registered, local entries only.
        assert
          builtins.attrNames self.pkgOverlays == [
            "default"
            "extra"
            "shared"
          ];
        assert self.pkgOverlays.default.key == "default";
        assert
          builtins.attrNames self.overlays == [
            "default"
            "extra"
            "shared"
          ];
        assert plain.producerDefault == "ok";
        assert plain.sharedApplied == 1;
        # Modules and lib overlays caisson contributed through
        # `projects` (`caisson/<name>`) are not exported by default;
        # the ones registered here are.
        assert
          builtins.attrNames self.modules.generic == [
            "named"
            "unnamed"
          ];
        assert
          builtins.attrNames self.modules.flake == [
            "default"
            "pusher"
          ];
        assert self.libOverlays == { };
        pkgs.runCommand "pkg-overlays-registry-producer" { } "touch $out";
    };
}
