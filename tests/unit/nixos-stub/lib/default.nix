# SPDX-License-Identifier: MIT
#
# The `lib` directory of the stand-in nixpkgs source tree, in the place
# `nixos/lib/eval-config.nix` and `nixos/lib/default.nix` import
# with `import ../../lib` when they are given no `lib`. Importing it is
# the failure this stand-in is built to expose: a NixOS evaluation
# that lands here runs on the library of the source tree it read its
# modules from rather than on the library the composition built, so
# the message names that.
throw ''
  The stand-in nixpkgs source tree of the unit tests was asked for its
  library: a NixOS evaluation ran `import ../../lib` because it was
  handed no `lib`. A NixOS evaluation runs on the composed
  library, which the nixos integration threads into the evaluator.
''
