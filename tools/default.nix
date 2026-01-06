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
  
  temper = pkgs.writeShellScriptBin "temper" (builtins.readFile ./temper);
  
  spr = pkgs.callPackage ./spr.nix { };
  git-absorb = pkgs.callPackage ./git-absorb.nix { };
in
{
  inherit cclsp claude-code-scripts beads tea temper spr git-absorb;

  all = [
    cclsp
    claude-code-scripts
    beads
    tea
    temper
    spr
    git-absorb
  ];
}