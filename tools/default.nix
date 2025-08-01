{ pkgs }:

let
  mcp-language-server = pkgs.callPackage ./mcp-language-server.nix { };
  claude-code-scripts = pkgs.callPackage ./claude-code-scripts.nix { };
in
{
  inherit mcp-language-server claude-code-scripts;
  
  all = [
    mcp-language-server
    claude-code-scripts
  ];
}