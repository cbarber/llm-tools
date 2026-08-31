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
          cursor-cli = import ./agents/cursor-cli { inherit pkgs tools; };
          opencode = import ./agents/opencode { inherit pkgs tools; };
          temper-acp = tools.temper-acp;
        };

        devShells = {
          inherit pkgs tools;
          claude-code = self.packages.${system}.claude-code;
          cursor-cli = self.packages.${system}.cursor-cli;
          opencode = self.packages.${system}.opencode;
          opencode-auth = import ./agents/opencode/auth.nix { inherit pkgs; };
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
                tools.fence
              ]
              ++ lib.optionals stdenv.isLinux [ bubblewrap ];
          };
        };
      }
    );
}
