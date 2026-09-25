{
  pkgs,
  tools,
  name,
  agentEnv,
  agentConfigDir,
  backendPackage,
  backendCommand,
  backendArgs ? [ ],
  backendSetup ? "",
}:

let
  backendComponent = pkgs.lib.escapeShellArgs ([ backendCommand ] ++ backendArgs);
  agentCommand = pkgs.lib.escapeShellArgs [
    "sacp-conductor"
    "agent"
    "temper-acp"
    backendComponent
  ];
in
pkgs.mkShell {
  name = "${name}-shell";

  buildInputs =
    with pkgs;
    [
      backendPackage
      findutils
      gh
      tea
      tools.temper-acp
      tools.toad
    ]
    ++ tools.all;

  shellHook = ''
    export ${agentEnv}=1
    export AGENT_ENV_CONFIG_DIR="${agentConfigDir}"
    export ACP_AGENT_COMMAND=${pkgs.lib.escapeShellArg agentCommand}
    export GIT_SEQUENCE_EDITOR="git-agent-sequence-editor"
    export GIT_EDITOR="git-agent-editor"
    export AGENT_SANDBOX_SCRIPT="${../tools/agent-sandbox.sh}"
    export AGENTS_SKILLS_DIR="${./skills}"
    export TOOLS_DIR="${../tools}"
    export FENCE_PATH="${tools.fence}/bin/fence"
    export IRON_PROXY_PATH="${tools.iron-proxy}/bin/iron-proxy"

    ${backendSetup}
    source ${./setup-acp-shell.sh}
  '';
}
