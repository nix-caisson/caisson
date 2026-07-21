# SPDX-License-Identifier: MIT
{ ... }:
{ config, ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.modules."test-class".exported = modules: modules;
  caisson.modules."disabled-class".export.enabled = false;

  perSystem =
    { pkgs, ... }:
    {
      checks.module-class-export-success =
        let
          testClassModule = config.flake.modules."test-class".exported;
        in
        assert config.flake.modules ? "test-class";
        assert config.flake.modules."test-class" ? exported;
        assert config.flake.modules ? "disabled-class";
        assert !(config.flake.modules."disabled-class" ? hidden);
        assert builtins.isFunction testClassModule || builtins.isAttrs testClassModule;
        assert (
          if builtins.isAttrs testClassModule then
            (testClassModule ? _class) || (testClassModule ? imports)
          else
            true
        );
        pkgs.runCommand "module-class-export-success" { } "touch $out";
    };
}
