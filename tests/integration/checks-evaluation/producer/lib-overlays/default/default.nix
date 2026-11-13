# SPDX-License-Identifier: MIT
#
# The lib overlay the producer exports, which the consumer finds in its
# registry as `producer/default`.
{ ... }:
{
  imports = [ ];
  overlay = _final: prev: {
    producer = (prev.producer or { }) // {
      marker = "from-the-producer-overlay";
    };
  };
}
