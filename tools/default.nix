{ pkgs, bun2nix }:

let
  cclsp = pkgs.callPackage ./cclsp.nix { inherit bun2nix; };
  claude-code-scripts = pkgs.callPackage ./claude-code-scripts.nix { };
in
{
  inherit cclsp claude-code-scripts;

  all = [
    cclsp
    claude-code-scripts
  ];
}