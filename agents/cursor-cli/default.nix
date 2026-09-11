{ pkgs, tools }:

import ../acp-runtime.nix {
  inherit pkgs tools;
  name = "cursor-cli";
  agentEnv = "CURSOR_CLI";
  agentConfigDir = "$HOME/.cursor";
  backendPackage = pkgs.cursor-cli;
  backendCommand = "cursor-agent";
  backendArgs = [ "acp" ];
}
