{ pkgs, lib, config, inputs, ... }:

{
  env.GREET = "devenv";

  packages = with pkgs; [ git libyaml typst];

  # https://devenv.sh/languages/
  languages.ruby.enable = true;

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
  '';

  enterShell = ''
  '';

  enterTest = ''
  '';

}
