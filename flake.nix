{
  description = "LLM agent tools and experimental environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    backlog-md.url = "github:MrLesk/Backlog.md";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      backlog-md,
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
          backlog = backlog-md.packages.${system}.backlog-md;
        };
      in
      {
        packages = {
          claude-code = import ./agents/claude-code { inherit pkgs tools; };
          opencode = import ./agents/opencode { inherit pkgs tools; };
        };

        devShells = {
          inherit pkgs tools;
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
                tools.spr
                shellcheck
                markdownlint-cli2
                nixfmt-rfc-style
                pre-commit
                bats
                opencode
                tools.backlog
              ]
              ++ lib.optionals stdenv.isLinux [ bubblewrap ];
          };
        };
      }
    );
}
