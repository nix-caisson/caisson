# SPDX-License-Identifier: MIT
#
# The `lib` directory of the stand-in nixpkgs tree, in the place
# `nixos/lib/eval-config.nix` and `nixos/lib/default.nix` reach for
# with `import ../../lib` when they are given no `lib`. Reaching it is
# the failure this stand-in is built to expose: a NixOS evaluation
# that lands here runs on the library of the tree it read its modules
# from rather than on the library the composition built, so the
# message names that.
throw ''
  The stand-in nixpkgs tree of the unit tests was asked for the library
  of its own tree: a NixOS evaluation reached `import ../../lib` because
  it was handed no `lib`. A NixOS evaluation runs on the composed
  library, which the nixos integration threads into the evaluator.
''
