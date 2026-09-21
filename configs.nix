# SPDX-License-Identifier: MIT
#
# The `configs` registration of caisson itself, shared by both tops:
# the configurations under configs/<class>/<name>, keyed the same way,
# so a top and a configuration that evaluates another beneath itself
# reach them as `lib.caisson-core.configs.<class>.<name>`.
lib: {
  structural = {
    # What caisson exports; both tops evaluate it beneath themselves.
    impl = lib.caisson.structural.mkModule ./configs/structural/impl;
    # The structural top.
    caisson = lib.caisson.structural.mkModule ./configs/structural/caisson;
  };
  flake = {
    # The flake top.
    caisson = lib.caisson.flake-parts.mkModule ./configs/flake-parts/caisson;
  };
}
