# Agent Sandboxing

Agents run in a deny-by-default sandbox via [fence](https://github.com/fencesandbox/fence), which wraps bubblewrap on Linux and Seatbelt on macOS behind one JSON config. The security model is the same on both platforms.

## Security Model

| Category | Access |
| --- | --- |
| Project directory | read-write |
| Temp workspace (`$AGENT_WORK_DIR`) | read-write |
| Agent config/cache dirs (`~/.config/opencode`, etc.) | read-write |
| Git identity files (`~/.gitconfig`, `~/.ssh/known_hosts`) | read-only |
| OS directories (`/usr`, `/bin`, `/lib`, `/nix`, etc.) | read-only |
| `~/.ssh` (keys), `~/.gnupg` | **denied** |
| Rest of home directory | **denied** |
| Other project directories | **denied** |

## Configuration

`agent-sandbox.sh` builds a per-session fence config with `defaultDenyRead: true` — only paths in `allowRead`/`allowWrite` are visible; everything else is absent. Path lists are built by `setup-sandbox-paths.sh` from the project directory, git dirs, agent config/cache dirs, and `$PATH`.

Key environment variables:

- `AGENT_SANDBOX_SSH=true` — allow reads+writes to `~/.ssh` (for git push over SSH)
- `AGENT_SANDBOX_BIND_HOME=true` — allow writes to the entire `$HOME` (breaks isolation)
- `SANDBOX_EXTRA_RO=path1:path2` — additional read-only paths
- `SANDBOX_EXTRA_RW=path1:path2` — additional read-write paths
- `SANDBOX_LOCAL_OUTBOUND_PORTS=5432:6379` — host loopback ports available inside Fence on Linux
- `FENCE_PATH` — path to the `fence` binary (set by the nix shellHook)

## Disabling the Sandbox

```bash
AGENT_SANDBOX=false nix develop .#claude-code
```
