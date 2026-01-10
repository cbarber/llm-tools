{
  lib,
  bun2nix,
  fetchFromGitHub,
}: let
  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };
in
  bun2nix.mkDerivation {
    pname = "cclsp";
    version = "0.6.1";

    src = fetchFromGitHub {
      owner = "ktnyt";
      repo = "cclsp";
      rev = "v0.6.1";
      hash = "sha256-7b8apHVh59Nyti0lQ8/etO++j1dOK07Rg78tP3yLEyQ=";
    };

    inherit bunDeps;

    module = "index.ts";

    # Disable bytecode compilation to support top-level await
    bunCompileToBytecode = false;

    meta = {
      description = "Claude Code LSP: seamlessly integrates LLM-based coding agents with Language Server Protocol servers";
      homepage = "https://github.com/ktnyt/cclsp";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [];
      mainProgram = "cclsp";
    };
  }
