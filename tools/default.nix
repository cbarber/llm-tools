{ pkgs, backlog }:

let
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
  rsync = pkgs.rsync;
  jq = pkgs.jq;
  curl = pkgs.curl;
in
{
  inherit
    claude-code-scripts
    tea
    spr
    git-absorb
    temper
    forge
    git-agent-sequence-editor
    git-agent-editor
    git-credential-nixsmith
    pre-commit
    backlog
    ;

  all = [
    claude-code-scripts
    tea
    spr
    git-absorb
    temper
    forge
    git-agent-sequence-editor
    git-agent-editor
    git-credential-nixsmith
    pre-commit
    rsync
    pkgs.jq
    pkgs.curl
    backlog
  ];
}
