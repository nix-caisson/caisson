# SPDX-License-Identifier: MIT
#
# The structural top's configuration: the shared configuration of
# what caisson exports, declared beneath this top under the name it
# is registered by (configs/structural/impl), with its exports merged
# into this top's exports. The configuration beneath sees this one
# without it, so the merge is made only in the evaluation that holds
# it.
{ ... }:
{ config, lib, ... }:
{
  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };

  # Passing the exports up is written here by hand until re-export
  # does it for every configuration declared beneath another. It reads
  # the result of the configuration beneath, which only the evaluation
  # that holds it can, hence the test; a module that only declares
  # configurations needs none.
  caisson.exports =
    if lib.caisson-core.evalManifest.childless then
      { }
    else
      config.caisson.structural.configurations.impl.outputs.exports;
}
