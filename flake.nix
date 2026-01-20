{
  description = "LLM agent tools and experimental environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    bun2nix.url = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      bun2nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ (import ./overlays) ];
        };
        tools = import ./tools {
          inherit pkgs;
          bun2nix = bun2nix.packages.${system}.default;
        };
      in
      {
        packages = {
          claude-code = import ./agents/claude-code { inherit pkgs tools; };
          opencode = import ./agents/opencode { inherit pkgs tools; };
        };

        devShells = {
          claude-code = self.packages.${system}.claude-code;
          opencode = self.packages.${system}.opencode;
          default = pkgs.mkShell {
            name = "dev-shell";
            buildInputs =
              with pkgs;
              [
                typescript
                typescript-language-server
                vtsls
                bun
              ];
          };
        };
      }
    );
}
