{
  description = "LLM agent tools and experimental environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
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
            buildInputs = with pkgs; [
              typescript
              typescript-language-server
              vtsls
              bun
              tools.spr
              shellcheck
              markdownlint-cli2
              nixfmt-rfc-style
              pre-commit
            ];
          };
        };
      }
    );
}
