{ pkgs, tools }:

import ../acp-runtime.nix {
  inherit pkgs tools;
  name = "cursor-cli";
  agentEnv = "CURSOR_CLI";
  agentConfigDir = "$HOME/.cursor";
  backendPackage = pkgs.cursor-cli;
  backendCommand = "cursor-agent";
  backendArgs = [
    "--trust"
    "acp"
  ];
  backendSetup = ''
    export AGENT_CLI_CREDENTIAL_STORE=file
    cursor_config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/cursor"
    mkdir -p "$cursor_config_dir"
    export SANDBOX_EXTRA_RW="''${SANDBOX_EXTRA_RW:+$SANDBOX_EXTRA_RW:}$cursor_config_dir"
    export SANDBOX_DIRECT_DOMAINS="''${SANDBOX_DIRECT_DOMAINS:+$SANDBOX_DIRECT_DOMAINS:}*.cursor.sh"
    unset cursor_config_dir
  '';
}
