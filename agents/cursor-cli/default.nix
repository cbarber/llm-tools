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
    export AGENT_CLI_CREDENTIAL_STORE=memory
    cursor_config_dir="$AGENT_ENV_CONFIG_DIR"
    mkdir -p "$cursor_config_dir"
    cursor_cli_config="$cursor_config_dir/cli-config.json"
    if [[ -f "$cursor_cli_config" ]]; then
      jq '.network.useHttp1ForAgent = true' "$cursor_cli_config" > "$cursor_cli_config.tmp"
    else
      jq -n '{network: {useHttp1ForAgent: true}}' > "$cursor_cli_config.tmp"
    fi
    mv "$cursor_cli_config.tmp" "$cursor_cli_config"
    export SANDBOX_EXTRA_RW="''${SANDBOX_EXTRA_RW:+$SANDBOX_EXTRA_RW:}$cursor_config_dir"
    unset cursor_cli_config cursor_config_dir
  '';
}
