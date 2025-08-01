{ pkgs }:

let
  mcp-language-server = pkgs.callPackage ./mcp-language-server.nix { };
in
{
  inherit mcp-language-server;
  
  all = [
    mcp-language-server
  ];
}