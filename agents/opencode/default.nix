{ pkgs, tools }:

pkgs.mkShell {
  name = "opencode-shell";

  buildInputs =
    with pkgs;
    [
      opencode
      cursor-cli
      coreutils
      findutils
      gh
      tea
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
      iproute2
    ]
    ++ tools.all;

  shellHook = ''
    export GIT_SEQUENCE_EDITOR="git-agent-sequence-editor"
    export GIT_EDITOR="git-agent-editor"
    export SETUP_CONFIG_SCRIPT="${./setup-config.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export TOOLS_DIR="${../../tools}"
    export FENCE_PATH="${tools.fence}/bin/fence"
    export IRON_PROXY_PATH="${tools.iron-proxy}/bin/iron-proxy"
    export AGENTS_SKILLS_DIR="${../../agents/skills}"
    export OPENCODE_PLUGIN_DIR="${./plugins}"
    export OPEN_CURSOR_PLUGIN_ENTRY="${tools.open-cursor}/lib/open-cursor/dist/plugin-entry.js"

    source ${./setup-shell.sh}
  '';
}
