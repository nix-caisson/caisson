# SPDX-License-Identifier: MIT
#
# The contribution this composition makes to the composed library,
# under the namespace named after the `name` the composition declares
# on mkLib. What the lib
# export publishes is this attribute set.
{ ... }:
{
  imports = [ ];
  overlay = _final: prev: {
    minimal-consumer = (prev.minimal-consumer or { }) // {
      marker = "from-the-minimal-consumer-overlay";
    };
  };
}
