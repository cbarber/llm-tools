# Agent Sandboxing

Agents run in a deny-by-default sandbox. The implementation differs by platform but the security model is the same.

## Security Model

| Category | Access |
|---|---|
| Project directory | read-write |
| Temp workspace (`$AGENT_WORK_DIR`) | read-write |
| Agent config/cache dirs (`~/.config/opencode`, etc.) | read-write |
| Git identity files (`~/.gitconfig`, `~/.ssh/known_hosts`) | read-only |
| OS directories (`/usr`, `/bin`, `/lib`, `/nix`, etc.) | read-only |
| `~/.ssh` (keys), `~/.gnupg` | **denied** |
| Rest of home directory | **denied** |
| Other project directories | **denied** |

## Linux (bubblewrap)

Uses bind mounts in a user namespace. Selected paths are mounted explicitly; everything else is absent from the namespace.

Key environment variables:
- `AGENT_SANDBOX_SSH=true` — bind-mount `~/.ssh` read-write (for git push over SSH)
- `AGENT_SANDBOX_BIND_HOME=true` — bind-mount entire `$HOME` read-write (breaks isolation)
- `SANDBOX_EXTRA_RO=path1:path2` — additional read-only paths
- `SANDBOX_EXTRA_RW=path1:path2` — additional read-write paths
- `BWRAP_EXTRA_PATHS=...` — deprecated alias for `SANDBOX_EXTRA_RW`

## macOS (sandbox-exec)

Uses Apple's `sandbox-exec` with a Scheme profile (`macos-sandbox-profile.sb`). Unlike bubblewrap, it cannot remap mounts, so the profile uses an explicit read allowlist.

Notable constraints:
- `(literal "/")` is required — the kernel reads the root inode before launching any sandboxed process; omitting it causes SIGABRT regardless of what else is allowed
- `(subpath ...)` is string prefix matching, not filesystem traversal — symlinks are not resolved
- `/Volumes` is excluded: `/Volumes/Macintosh HD → /` makes it a theoretical traversal vector
- `/private` is required for `TMPDIR` (`/private/var/folders/.../T/`)
- Home directory reads are restricted to specific paths (git config, agent SSH keys); no blanket `$HOME` access

Same environment variables as Linux apply.

## Disabling the Sandbox

```bash
AGENT_SANDBOX=false nix develop .#claude-code
```
