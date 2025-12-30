# Agent Sandboxing

This directory contains tools for sandboxing CLI agents to restrict filesystem access.

## Platform Support

- **Linux**: Bubblewrap (namespace-based isolation with bind mounts)
- **macOS**: sandbox-exec (TrustedBSD MAC policy with path whitelisting)

## Files

- `agent-sandbox.sh` - Platform-detecting wrapper (delegates to Linux or macOS implementation)
- `macos-sandbox.sh` - macOS sandbox-exec implementation
- `macos-sandbox-profile.sb` - TrustedBSD policy profile for macOS
- `test-agent-sandbox.sh` - Comprehensive test suite to validate sandbox behavior (Linux)
- `SANDBOX.md` - This documentation

## Quick Start

### Prerequisites

Bubblewrap must be available in your PATH. Add it to agent shell buildInputs:

```nix
# In agents/*/default.nix
buildInputs = [
  pkgs.bubblewrap
  # ... other packages
];
```

### Basic Usage

```bash
# Run a command in the sandbox
tools/agent-sandbox.sh ls -la

# Run git commands
tools/agent-sandbox.sh git status

# Run an interactive shell
tools/agent-sandbox.sh bash
```

### Running Tests

```bash
# Validate sandbox behavior
tools/test-agent-sandbox.sh
```

## Sandbox Configuration

### Default Behavior

The sandbox provides:

- **Read-write access**: Current project directory
- **Read-only access**: /nix store
- **Read-write access**: Temporary work directory at `/tmp/agent-work`
- **Blocked access**: HOME, /etc, other projects, system directories
- **Network**: Enabled
- **Auto-cleanup**: Work directory removed on exit

### Environment Variables

#### AGENT_WORK_DIR

Automatically set inside the sandbox to `/tmp/agent-work`. Use this for temporary files:

```bash
tools/agent-sandbox.sh bash -c 'echo "test" > $AGENT_WORK_DIR/file.txt'
```

#### AGENT_SANDBOX_SSH

Enable read-only access to ~/.ssh for git authentication:

```bash
AGENT_SANDBOX_SSH=true tools/agent-sandbox.sh git push
```

#### AGENT_SANDBOX_BIND_HOME

**⚠️ WARNING**: Breaks isolation! Only use for debugging:

```bash
AGENT_SANDBOX_BIND_HOME=true tools/agent-sandbox.sh command
```

## Integration with Agent Shells

### Option 1: Wrapper Command (Recommended)

Use `agent-sandbox` as a prefix:

```bash
nix develop .#claude-code
agent-sandbox claude
```

### Option 2: Environment Variable

```bash
AGENT_SANDBOX=true nix develop .#claude-code
```

### Option 3: Always-On

Modify shell Hook in `agents/*/default.nix` to always use sandbox:

```nix
shellHook = ''
  # Wrap agent command
  alias claude="agent-sandbox claude"
  
  # Auto-launch sandboxed agent
  exec agent-sandbox claude
'';
```

## Test Suite

The test suite (`test-agent-sandbox.sh`) validates:

1. **Security**:
   - Blocks access to files outside project
   - Blocks access to HOME directory
   - Allows access to project files
   - /nix store is read-only

2. **Functionality**:
   - Work directory creation and cleanup
   - Git access and commands
   - Basic shell utilities available
   - Network access enabled
   - /proc filesystem accessible

3. **Performance**:
   - Measures overhead (should be <1s for 10 operations)

4. **Optional Features**:
   - SSH key access control via AGENT_SANDBOX_SSH

### Test Output

```
======================================
Agent Sandbox Validation Tests
======================================
[TEST 1] File access outside project directory
✓ PASS: Sandbox correctly blocked access to file outside project
[TEST 2] Access to HOME directory
✓ PASS: Sandbox correctly blocked access to HOME directory
...
======================================
Test Summary
======================================
Tests run:    14
Tests passed: 14
Tests failed: 0

✓ All tests passed!
```

## How It Works

### Linux (Bubblewrap)

The sandbox uses bubblewrap to create a restricted environment:

1. **Namespace Isolation**: Unshares all namespaces except network
2. **Bind Mounts**: Selectively mounts directories:
   - `/nix` (read-only) - Nix store access
   - Current directory (read-write) - Project files
   - Temp workspace (read-write) - Agent work directory
   - `/dev`, `/proc` (device access)
   - Agent config directories (read-write) - `~/.config/opencode`, `~/.claude`, etc.
   - Agent SSH keys (read-only) - `~/.ssh/agent-*`
3. **Cleanup**: Trap ensures temp directory is removed on exit
4. **Die-with-parent**: Sandbox dies if wrapper process exits

### macOS (sandbox-exec)

The sandbox uses sandbox-exec with a TrustedBSD MAC policy:

1. **Default Deny**: Starts with minimal permissions, then whitelists specific paths
2. **Read-Only System Access**: 
   - Nix store, system libraries, SSL certificates
   - DNS resolution files (`/etc/resolv.conf`, `/etc/hosts`)
   - User/group information (`/etc/passwd`, `/etc/group`)
3. **Read-Write Agent Access**:
   - Current project directory
   - Agent config directories (`~/.config/opencode`, `~/.claude`, etc.)
   - Language tooling caches (`~/.cargo`, `~/.npm`, etc.)
   - Temporary directories (`$TMPDIR`, `/tmp`)
4. **Blocked Access**:
   - Personal SSH keys (`~/.ssh/id_rsa`, etc.) - only agent keys allowed
   - Personal config directories (`~/.config/gh`, `~/.aws`, etc.)
   - Documents, Downloads, Desktop, and other personal directories
   - API keys and credentials outside agent directories

## Security Model

### Previous Codex-Style Implementation (INSECURE)

The original macOS sandbox profile (copied from OpenAI Codex) used:
```scheme
(allow file-read*)  ;; Global read access - SECURITY THEATER!
```

This allowed agents to read **ANY** file on the system, including:
- Personal SSH keys in `~/.ssh/id_rsa`
- GitHub CLI tokens in `~/.config/gh/hosts.yml`
- AWS credentials in `~/.aws/credentials`
- Browser session data
- Personal documents

**This made sandboxing security theater** - write restrictions prevented damage, but agents could exfiltrate sensitive data.

### Current Whitelist-Based Implementation (SECURE)

The fixed macOS sandbox uses explicit path whitelisting (matching Linux bubblewrap):
```scheme
(allow file-read*
  (subpath "/nix")                     ;; Nix store only
  (subpath (param "PROJECT_DIR"))      ;; Current project only
  (subpath (param "HOME_CLAUDE"))      ;; Agent configs only
  ;; ... specific agent paths only
)
```

Agents can ONLY read:
- System paths needed for basic functionality (Nix, libraries, DNS)
- Current project directory
- Their own config/cache directories
- Agent-specific SSH keys (`~/.ssh/agent-*`)

**Everything else is blocked** - personal files, credentials, and sensitive data are protected.

## Troubleshooting

### "bubblewrap (bwrap) not found"

Add bubblewrap to your shell:

```bash
nix develop .#claude-code  # Should have bubblewrap in buildInputs
# Or temporarily:
nix-shell -p bubblewrap
```

### "Permission denied" errors

Check if user namespaces are enabled:

```bash
cat /proc/sys/kernel/unprivileged_userns_clone  # Should be 1
```

If disabled, enable with:

```bash
sudo sysctl kernel.unprivileged_userns_clone=1
```

### Git authentication fails

Enable SSH key access:

```bash
AGENT_SANDBOX_SSH=true tools/agent-sandbox.sh git push
```

### Performance is slow

Check the performance test results:

```bash
tools/test-agent-sandbox.sh | grep -A 5 "Performance"
```

Overhead should be <1s for 10 operations. If higher, check:
- System load
- User namespace configuration
- Filesystem performance

## Design Decisions

### Linux: Why bubblewrap over alternatives?

- **No root required**: Works with user namespaces
- **Fine-grained control**: Selective bind mounts
- **Battle-tested**: Used by Flatpak
- **Lightweight**: Minimal overhead
- **Available in nixpkgs**: Easy integration

### macOS: Why sandbox-exec?

- **Built into macOS**: No external dependencies
- **Kernel-enforced**: TrustedBSD MAC policies at kernel level
- **Parameterized profiles**: Clean separation of policy and paths
- **Mature**: Used by App Sandbox and other macOS security features

### Why not chroot?

Requires root/CAP_SYS_CHROOT and complex setup.

### Why not firejail?

Less flexible, opinionated defaults, larger attack surface.

### Why explicit whitelisting instead of Codex-style global read access?

**Security posture**: Global `file-read*` allows agents to exfiltrate:
- Personal SSH keys and API tokens
- Browser session cookies and credentials
- Documents and personal files
- Anything readable on the system

**Whitelist approach**: Agents can ONLY read what they need for functionality:
- System paths (Nix, libraries, DNS)
- Current project
- Agent-specific configs and caches

This prevents data exfiltration while maintaining full agent functionality.

### Why opt-in by default?

Sandboxing may break existing workflows. Better to let users opt-in once they understand the trade-offs.

## Future Improvements

1. **Auto-detect git SSH needs**: Automatically enable AGENT_SANDBOX_SSH when git operations fail
2. **Configurable bind mounts**: Allow users to specify additional directories
3. **Audit logging**: Log all filesystem access attempts
4. **Integration with nix shells**: Seamless activation via environment variable
5. **Performance optimization**: Cache namespace creation for repeated invocations

## References

- [Bubblewrap documentation](https://github.com/containers/bubblewrap)
- [Linux user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Flatpak sandboxing](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
