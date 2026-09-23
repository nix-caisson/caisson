# SPDX-License-Identifier: MIT
#
# A stand-in for `modules/lib/default.nix` of the home-manager source:
# the function the integration composes as the `hm` entry. It has that
# file's signature, `{ lib }:`, and the two properties the entry
# depends on.
#
# Its functions reach the library they were built over, so reading
# `reachesLib` shows which library the entry composed `hm` on top of.
# `dag.entryAnywhere` calls back through `lib.hm`, the way the real
# `generators` and `deprecations` call `lib.hm.dag` and
# `lib.hm.strings`, so a test that forces it proves the
# self-reference resolves through the composed fixpoint rather than a
# library rebuilt beside it.
{ lib }:
rec {
  # The marker of the library this `hm` was built over.
  reachesLib = lib.caissonMarker or null;

  dag = {
    entryAnywhere = data: {
      inherit data;
      # The call back through the fixpoint.
      viaFixpoint = lib.hm.reachesLib;
    };
  };

  maintainers = {
    home-manager-stub-maintainer = {
      name = "home-manager stub maintainer";
    };
  };
}
