# SPDX-License-Identifier: MIT
#
# The two selections every integration draws from the registry of its
# class (`lib.caisson-core.modules.<class>` of the composition the
# evaluation runs in), by entry name:
#
#   coreModules          every entry named `core`: the local `core` and
#                        a consumed project's `<project>/core`. They are
#                        the framework module of the class, forced into
#                        every evaluation before anything the
#                        evaluation selects.
#   defaultModuleImports every entry named `default`, likewise: the
#                        default default, what `moduleImports` selects
#                        when the evaluation names nothing.
#
# Any project a composition lists may register either, for any class.
# A `core` is the big hammer, for a module the class cannot function
# without; a `default` is what the project gives every configuration
# of the class unless the configuration selects otherwise. The
# integration's own core arrives through its closure as well, so it
# is there even when the integration was registered by hand rather
# than through `projects`; the module system deduplicates the two
# copies by key.
let

  named =
    leaf: name:
    let
      n = builtins.stringLength name;
      l = builtins.stringLength leaf;
    in
    name == leaf || (n > l && builtins.substring (n - l - 1) (l + 1) name == "/${leaf}");

  select =
    leaf: registry:
    builtins.map (name: registry.${name}) (builtins.filter (named leaf) (builtins.attrNames registry));

in
{
  coreModules = select "core";
  defaultModuleImports = select "default";
}
