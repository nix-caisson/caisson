# SPDX-License-Identifier: MIT
#
# Every integration's entry point takes exactly the caisson-shaped
# arguments (configModule, moduleImports, specialArgs, pkgSets,
# ecosystemSrc, and a target's own few) and composes the evaluator's
# call from them. Nothing else is forwarded: an evaluator argument
# handed in directly would be silently overwritten, silently dropped,
# or surface as a conflict deep inside the evaluator. The
# `...WithEcosystemArgs` twin of each entry point is the way to the
# evaluator's full surface: it takes the same arguments plus
# `ecosystemArgs`, merged over the composed call verbatim, last.
#
# context:  the entry point, for the message.
# accepted: the argument names it takes.
# hints:    per-name pointers for the common mistakes (an evaluator
#           name where a caisson name exists).
# open:     the twin's name, or null when checking the twin itself.
{
  context,
  accepted,
  hints ? { },
  open ? null,
}:
args:
let
  unknown = builtins.filter (name: !(builtins.elem name accepted)) (builtins.attrNames args);
  name = builtins.head unknown;
  message =
    if hints ? ${name} then
      "${context} does not accept `${name}`: ${hints.${name}}"
    else if open != null then
      "${context} does not accept `${name}`; it takes ${builtins.concatStringsSep ", " accepted}. The evaluator's own arguments are available through ${open}, in `ecosystemArgs`."
    else
      "${context} does not accept `${name}`; it takes ${builtins.concatStringsSep ", " accepted}. Evaluator arguments go in `ecosystemArgs`.";
in
if unknown == [ ] then args else throw message
