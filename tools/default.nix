{ pkgs, bun2nix }:

let
  beads = pkgs.buildGoModule {
    pname = "beads";
    version = "0.38.0";

    src = pkgs.fetchFromGitHub {
      owner = "steveyegge";
      repo = "beads";
      rev = "v0.38.0";
      hash = "sha256-Me4bD/laKBBrLH4Qv4ywlFVt8tOPNwDohk41nHQpc8Q=";
    };

    subPackages = [ "cmd/bd" ];
    doCheck = false;
    vendorHash = "sha256-ovG0EWQFtifHF5leEQTFvTjGvc+yiAjpAaqaV0OklgE=";

    nativeBuildInputs = [ pkgs.git ];

    meta = with pkgs.lib; {
      description = "beads (bd) - An issue tracker designed for AI-supervised coding workflows";
      homepage = "https://github.com/steveyegge/beads";
      license = licenses.mit;
      mainProgram = "bd";
      maintainers = [ ];
    };
  };
  
  cclsp = pkgs.callPackage ./cclsp.nix { inherit bun2nix; };
  claude-code-scripts = pkgs.callPackage ./claude-code-scripts.nix { };
  tea = pkgs.tea;
  
  spr = pkgs.callPackage ./spr { };
  git-absorb = pkgs.git-absorb;
  
  temper = pkgs.writeShellScriptBin "temper" (builtins.readFile ./temper);
  git-agent-sequence-editor = pkgs.writeShellScriptBin "git-agent-sequence-editor" (builtins.readFile ./git-agent-sequence-editor);
  git-agent-editor = pkgs.writeShellScriptBin "git-agent-editor" (builtins.readFile ./git-agent-editor);
  pre-commit = pkgs.pre-commit;
in
{
  inherit cclsp claude-code-scripts beads tea spr git-absorb temper git-agent-sequence-editor git-agent-editor pre-commit;

  all = [
    cclsp
    claude-code-scripts
    beads
    tea
    spr
    git-absorb
    temper
    git-agent-sequence-editor
    git-agent-editor
    pre-commit
  ];
}