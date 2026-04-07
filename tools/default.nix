{ pkgs }:

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

  claude-code-scripts = pkgs.callPackage ./claude-code-scripts.nix { };
  tea = pkgs.tea;

  spr = pkgs.callPackage ./spr { };
  git-absorb = pkgs.git-absorb;

  temper = pkgs.writeShellScriptBin "temper" (builtins.readFile ./temper);
  forge = pkgs.stdenv.mkDerivation {
    pname = "forge";
    version = "0.1.0";
    src = ./.;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin
      cp ${./forge} $out/bin/forge
      cp ${./common-helpers.sh} $out/bin/common-helpers.sh
      chmod +x $out/bin/forge
    '';
  };
  git-agent-sequence-editor = pkgs.writeShellScriptBin "git-agent-sequence-editor" (
    builtins.readFile ./git-agent-sequence-editor
  );
  git-agent-editor = pkgs.writeShellScriptBin "git-agent-editor" (
    builtins.readFile ./git-agent-editor
  );
  git-credential-nixsmith = pkgs.writeShellScriptBin "git-credential-nixsmith" (
    builtins.readFile ./git-credential-nixsmith
  );
  pre-commit = pkgs.pre-commit;
in
{
  inherit
    claude-code-scripts
    beads
    tea
    spr
    git-absorb
    temper
    forge
    git-agent-sequence-editor
    git-agent-editor
    git-credential-nixsmith
    pre-commit
    ;

  all = [
    claude-code-scripts
    beads
    tea
    spr
    git-absorb
    temper
    forge
    git-agent-sequence-editor
    git-agent-editor
    git-credential-nixsmith
    pre-commit
  ];
}
