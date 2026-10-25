{
  lib,
  stdenv,
  makeWrapper,
  bats,
  coreutils,
  git,
  jq,
  libnotify,
  work-record,
}:

stdenv.mkDerivation {
  pname = "claude-code-scripts";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    jq
    libnotify
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Copy scripts to bin directory
    cp ${./claude-code-scripts}/notify $out/bin/
    cp ${./claude-code-scripts}/stop-continue $out/bin/
    cp ${./claude-code-scripts}/compact-resume $out/bin/
    cp ${./claude-code-scripts}/herdr-renew $out/bin/
    cp ${./claude-code-scripts}/common-helpers.sh $out/bin/
    cp ${./claude-code-scripts}/git-to-bare-worktree $out/bin/

    # Make scripts executable
    chmod +x $out/bin/*

    # Wrap scripts with runtime dependencies
    for script in notify stop-continue compact-resume; do
      wrapProgram $out/bin/$script \
        --prefix PATH : ${
          lib.makeBinPath [
            jq
            libnotify
          ]
        }
    done

    # Runs outside the sandbox, so nothing on the launching PATH, which holds
    # sandbox-writable directories, may be executed.
    wrapProgram $out/bin/herdr-renew \
      --set PATH ${
        lib.makeBinPath [
          coreutils
          jq
          work-record
        ]
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    bats
    git
    jq
    work-record
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR HERDR_RENEW_BIN=$out/bin/herdr-renew bats ${./claude-code-scripts}/test-herdr-renew-path.bats
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Claude Code utility scripts for linting, testing, and notifications";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
