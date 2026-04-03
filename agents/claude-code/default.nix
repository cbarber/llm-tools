{ pkgs, tools }:

pkgs.mkShell {
  name = "claude-code-shell";

  buildInputs =
    with pkgs;
    [
      claude-code
      findutils
      gh
      tea
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ bubblewrap ]
    ++ tools.all;

  shellHook = ''
    export CLAUDECODE=1
    export GIT_SEQUENCE_EDITOR="git-agent-sequence-editor"
    export GIT_EDITOR="git-agent-editor"
    export SETTINGS_TEMPLATE="${./settings.template.json}"
    export SETUP_SETTINGS_SCRIPT="${./setup-settings.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export AGENTS_SKILLS_DIR="${../../agents/skills}"
    export TOOLS_DIR="${../../tools}"
    ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''export BWRAP_PATH="${pkgs.bubblewrap}/bin/bwrap"''}
    export BD_BRANCH="''${BD_BRANCH:-beads-sync}"

    source ${./setup-shell.sh}
  '';
}
