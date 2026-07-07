{ pkgs, tools }:

pkgs.mkShell {
  name = "opencode-shell";

  buildInputs =
    with pkgs;
    [
      opencode
      findutils
      gh
      tea
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
      iproute2
      coreutils
    ]
    ++ tools.all;

  shellHook = ''
    export GIT_SEQUENCE_EDITOR="git-agent-sequence-editor"
    export GIT_EDITOR="git-agent-editor"
    export SETUP_CONFIG_SCRIPT="${./setup-config.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export TOOLS_DIR="${../../tools}"
    export FENCE_PATH="${tools.fence}/bin/fence"
    export AGENTS_SKILLS_DIR="${../../agents/skills}"
    export OPENCODE_PLUGIN_DIR="${./plugins}"

    source ${./setup-shell.sh}
  '';
}
