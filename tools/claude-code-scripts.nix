{ lib, stdenv, makeWrapper, jq, libnotify }:

stdenv.mkDerivation {
  pname = "claude-code-scripts";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ jq libnotify ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    
    # Copy scripts to bin directory
    cp ${./claude-code-scripts}/smart-lint $out/bin/
    cp ${./claude-code-scripts}/smart-test $out/bin/
    cp ${./claude-code-scripts}/notify $out/bin/
    cp ${./claude-code-scripts}/common-helpers.sh $out/bin/
    cp ${./claude-code-scripts}/git-to-bare-worktree $out/bin/
    
    # Make scripts executable
    chmod +x $out/bin/*
    
    # Wrap scripts with runtime dependencies
    for script in smart-lint smart-test notify; do
      wrapProgram $out/bin/$script \
        --prefix PATH : ${lib.makeBinPath [ jq libnotify ]}
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Claude Code utility scripts for linting, testing, and notifications";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}