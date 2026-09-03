# SPDX-License-Identifier: MIT
# A flake-parts consumer that applies only the nixpkgs-interface flake
# module: it can register an overlay, keeps flake-parts' own `pkgs`, and
# gets no package-set machinery.
{ ... }:
{
  config,
  lib,
  self,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  # The interface module declares only the overlay registry: no
  # pkgSets, no export switches, no package-set machinery.

  caisson.nixpkgs.overlays.all.marker = lib.caisson.nixpkgs.mkPolyfillOverlay (
    _final: _prev: {
      interfaceMarker = "ok";
    }
  );

  perSystem =
    { pkgs, ... }:
    {
      checks.nixpkgs-interface-consumer-success =
        let
          registered = config.caisson.nixpkgs.overlays.all.marker "nixpkgs-interface-consumer";
        in
        # Only the registry is declared; no pkgSets, no export switches.
        assert builtins.attrNames config.caisson.nixpkgs == [ "overlays" ];
        assert builtins.attrNames config.caisson.nixpkgs.overlays == [ "all" ];
        # The registered overlay is usable by whoever selects it.
        assert (registered { } { }).interfaceMarker == "ok";
        # Nothing applied it: `pkgs` is flake-parts' own nixpkgs instance.
        assert !(pkgs ? interfaceMarker);
        assert pkgs ? runCommand;
        # Nothing exported it.
        assert self.overlays == { };
        pkgs.runCommand "nixpkgs-interface-consumer-success" { } "touch $out";
    };
}
