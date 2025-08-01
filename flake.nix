{
  description = "LLM agent tools and experimental environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        tools = import ./tools { inherit pkgs; };
      in
      {
        packages = {
          claude-code = import ./agents/claude-code { inherit pkgs tools; };
        };

        devShells = {
          claude-code = self.packages.${system}.claude-code;
          default = self.packages.${system}.claude-code;
        };
      });
}