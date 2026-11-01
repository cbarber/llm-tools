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
    cp ${./claude-code-scripts}/context-status $out/bin/
    cp ${./claude-code-scripts}/context-size.sh $out/bin/
    cp ${./claude-code-scripts}/compact-resume $out/bin/
    cp ${./claude-code-scripts}/session-model $out/bin/
    cp ${./claude-code-scripts}/herdr-renew $out/bin/
    cp ${./claude-code-scripts}/common-helpers.sh $out/bin/
    cp ${./claude-code-scripts}/git-to-bare-worktree $out/bin/
    cp ${./claude-code-scripts}/renewal-request.sh $out/bin/

    # Make scripts executable
    chmod +x $out/bin/*

    # Wrap scripts with runtime dependencies
    for script in notify session-model; do
      wrapProgram $out/bin/$script \
        --prefix PATH : ${
          lib.makeBinPath [
            jq
            libnotify
          ]
        }
    done

    wrapProgram $out/bin/stop-continue \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          git
          jq
          work-record
        ]
      }

    wrapProgram $out/bin/compact-resume \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          jq
          work-record
        ]
      }

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

    wrapProgram $out/bin/context-status \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          jq
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
    HOME=$TMPDIR CONTEXT_STATUS_BIN=$out/bin/context-status bats ${./claude-code-scripts}/test-context-status-path.bats
    HOME=$TMPDIR HERDR_RENEW_BIN=$out/bin/herdr-renew bats ${./claude-code-scripts}/test-herdr-renew-path.bats
    HOME=$TMPDIR STOP_CONTINUE_BIN=$out/bin/stop-continue bats ${./claude-code-scripts}/test-stop-continue-path.bats
    HOME=$TMPDIR COMPACT_RESUME_BIN=$out/bin/compact-resume bats ${./claude-code-scripts}/test-compact-resume-path.bats
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Claude Code hooks (notify, work continuation, compaction resume, session model), the context status line, the Herdr context-renewal helper, and git-to-bare-worktree";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
