# SPDX-License-Identifier: MIT
#
# The pkgs-dependent tooling: helpers that need a package set at use
# time. The composition machinery lives in caisson-core (the
# caisson-core input) and reaches composed libraries as the
# `caisson-core` namespace mkLib composes in.
{ entries, ... }:

{

  imports = [ entries.nixpkgs-lib ];

  overlay = final: prev: {

    caisson = (prev.caisson or { }) // {

      eval-weight = import ./eval-weight { lib = final; };

      mkMemoizedDerivationRead = import ./mk-memoized-derivation-read.nix { lib = final; };

    };

  };

}
