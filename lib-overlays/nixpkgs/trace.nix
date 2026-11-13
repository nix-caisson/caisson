# SPDX-License-Identifier: MIT
#
# The trace of a package set: how each of its packages was made.
# nixpkgs keeps no link from the result of an override to what it
# overrode, so the trace is recorded while the set is built. A traced
# set is the same set, built on the same lib with `callPackageWith`
# replaced by a version that records each call. Every derivation a
# traced `callPackage` returns carries `caissonTrace`, and so does
# every derivation its `override`, `overrideAttrs` and
# `overrideDerivation` return:
#
#   step      "callPackage", "override", "overrideAttrs" or
#             "overrideDerivation"
#   from      the derivation the step was applied to, null for the
#             `callPackage` at the bottom of the chain
#   touched   the names the step gave: the arguments of a
#             `callPackage` or an `override`, null for a step that
#             takes a function
#   position  the file and line number of the argument set the caller
#             wrote, null where there is none
#
# The record of the `callPackage` at the bottom also holds `file`, the
# file of the package function where it is a path, `resolved`, the
# arguments the function takes that came from the scope, and `set`,
# the package set the call resolved from.
#
# The trace is attributes beside the derivation, so every derivation
# keeps its `drvPath`. Each attribute is lazy, and a set that is not
# traced is not touched.
{
  # The package set the trace is of, as `{ config; system; }`.
  set,
}:
lib:
let
  positionOf =
    attrs:
    let
      names = builtins.attrNames attrs;
      position = if names == [ ] then null else builtins.unsafeGetAttrPos (builtins.head names) attrs;
    in
    if position == null then
      null
    else
      {
        inherit (position) file line;
      };

  isDerivation = value: builtins.isAttrs value && (value.type or null) == "derivation";

  # `f` with its call replaced by `g`, keeping what `f` carries beside
  # its call, such as the `__functionArgs` of an `override`.
  replaceCall = f: g: if builtins.isAttrs f then f // { __functor = _self: g; } else g;

  # `value` with `record` as its trace, and its `override`,
  # `overrideAttrs` and `overrideDerivation` tracing what they return.
  traced =
    value: record:
    if !(isDerivation value) then
      value
    else
      let
        self =
          value
          // {
            caissonTrace = record;
          }
          // (
            if value ? override then
              {
                override = replaceCall value.override (
                  newArgs:
                  traced (value.override newArgs) {
                    step = "override";
                    from = self;
                    touched = if builtins.isAttrs newArgs then builtins.attrNames newArgs else null;
                    position = if builtins.isAttrs newArgs then positionOf newArgs else null;
                  }
                );
              }
            else
              { }
          )
          // (
            if value ? overrideAttrs then
              {
                overrideAttrs = replaceCall value.overrideAttrs (
                  f:
                  traced (value.overrideAttrs f) {
                    step = "overrideAttrs";
                    from = self;
                    touched = if builtins.isAttrs f then builtins.attrNames f else null;
                    position = if builtins.isAttrs f then positionOf f else null;
                  }
                );
              }
            else
              { }
          )
          // (
            if value ? overrideDerivation then
              {
                overrideDerivation = replaceCall value.overrideDerivation (
                  f:
                  traced (value.overrideDerivation f) {
                    step = "overrideDerivation";
                    from = self;
                    touched = null;
                    position = null;
                  }
                );
              }
            else
              { }
          );
      in
      self;

  callPackageWith =
    autoArgs: fn: args:
    let
      function = if builtins.isFunction fn then fn else import fn;
      wanted = builtins.attrNames (builtins.functionArgs function);
    in
    traced (lib.callPackageWith autoArgs fn args) {
      step = "callPackage";
      from = null;
      touched = builtins.attrNames args;
      position = positionOf args;
      file = if builtins.isPath fn || builtins.isString fn then toString fn else null;
      resolved = builtins.filter (name: !(args ? ${name}) && autoArgs ? ${name}) wanted;
      inherit set;
    };
in
lib
// {
  inherit callPackageWith;
  customisation = lib.customisation // {
    inherit callPackageWith;
  };
}
