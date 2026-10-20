# SPDX-License-Identifier: MIT
#
# The warning a drift check prints, run. `inputs` is the dependency pool
# of the checks partition with `caisson` set to the tree itself.
#
# The nvf configuration `editor` inside a hjem configuration that is a
# top checks, when it is activated, the marker of the hjem
# configuration. The check runs its `activate` in the build sandbox,
# where the marker does not exist, and compares what it prints to
# standard error, up to the activation step that needs a Nix daemon,
# with the warning the drift check is written to print. The names in
# the warning are in backticks, which the shell must print and not
# run.
{ inputs }:
let
  probe = import ../hjem-system { inherit inputs; };
  inherit (probe) pkgs system;

  top = probe.lib.caisson.hjem.mkTopConfiguration {
    configModule =
      { lib, ... }:
      {
        imports = [ probe.user ];
        user = "probe";
        directory = "/home/probe";
        caisson.nvf.configurations.editor = lib.caisson.nvf.mkConfiguration {
          ecosystemSrc = inputs.nvf;
          configModule.vim.viAlias = true;
        };
      };
  };

  editor = top.caisson.manifest.children.system.${system}.children.nvf.editor.outputs;

  expected = pkgs.writeText "expected" ''
    WARNING: /home/probe/.local/state/caisson/markers/hjem-default.json does not exist.
      the nvf configuration `editor` is declared inside the hjem configuration `(unnamed)`,
      and the activation of the hjem configuration `(unnamed)` has not recorded what it applied.
      Activate the hjem configuration `(unnamed)` as this configuration was built with it,
      or set `caisson.drift.warn` to false in the nvf configuration `editor`.
  '';
in
pkgs.runCommand "drift-message" { } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  ${editor.activationPackage}/activate 2> stderr || true
  head -n 5 stderr > warning
  diff -u ${expected} warning
  touch $out
''
