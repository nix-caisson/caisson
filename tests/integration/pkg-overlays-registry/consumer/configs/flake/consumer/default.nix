# SPDX-License-Identifier: MIT
#
# The consumer's flake: package sets draw on its registry and on the
# producer registry, and the exports keep what the consumer registers
# itself plus what its selectors name.
{ ... }:
{
  inputs,
  lib,
  self,
  ...
}:
let
  local = lib.filterAttrs (name: _: !(lib.hasInfix "/" name));
in
{
  systems = [ "x86_64-linux" ];

  caisson = {
    nixpkgs = {
      pkgSets = {
        pkgs.pkgFunction = import inputs.nixpkgs;
        # Selects the extra entry of the producer by name, in place of
        # the default selection.
        withExtra = {
          pkgFunction = import inputs.nixpkgs;
          pkgOverlayImports = registry: [ registry."producer/extra" ];
        };
      };
    };
    # A project's entry leaves when a selector names it.
    pkgOverlays.exported = registry: local registry // { inherit (registry) "producer/extra"; };
    modules.generic.exported = modules: local modules // { inherit (modules) "producer/named"; };
  };

  perSystem =
    { pkgs, pkgSets, ... }:
    {
      checks.pkg-overlays-registry-consumer =
        # The default selection: both defaults, the shared entry once,
        # and the extra entry only where a set names it.
        assert pkgs.consumerDefault == "ok";
        assert pkgs.producerDefault == "ok";
        assert pkgs.sharedApplied == 1;
        assert !(pkgs ? producerExtra);
        assert pkgSets.withExtra.producerExtra;
        assert !(pkgSets.withExtra ? producerDefault);
        # Exports: what the consumer registers itself, and the project
        # entries a selector names; no other producer entry.
        assert
          builtins.attrNames self.pkgOverlays == [
            "default"
            "producer/extra"
          ];
        assert
          builtins.attrNames self.overlays == [
            "default"
            "producer/extra"
          ];
        assert builtins.attrNames self.modules.generic == [ "producer/named" ];
        assert self.libOverlays == { };
        pkgs.runCommand "pkg-overlays-registry-consumer" { } "touch $out";
    };
}
