# SPDX-License-Identifier: MIT
#
# The pkgs-dependent tooling: helpers that need a package set at use
# time. The composition machinery this directory used to hold lives in
# caisson-core (vendored under vendor/caisson-core) and reaches
# composed libraries through mkLib's `caisson-core` namespace
# injection.
{ ... }:

{

  imports = [ ];

  overlay = final: prev: {

    caisson = (prev.caisson or { }) // {

      eval-weight = import ./eval-weight { lib = final; };

      mkMemoizedDerivationRead = import ./mk-memoized-derivation-read.nix { lib = final; };

    };

  };

}
