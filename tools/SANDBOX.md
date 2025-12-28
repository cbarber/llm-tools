# Agent Sandboxing with Bubblewrap

This directory contains tools for sandboxing CLI agents using bubblewrap to restrict filesystem access.

## Files

- `agent-sandbox.sh` - Wrapper script that runs commands in a bubblewrap sandbox
- `test-agent-sandbox.sh` - Comprehensive test suite to validate sandbox behavior
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

The sandbox uses bubblewrap to create a restricted environment:

1. **Namespace Isolation**: Unshares all namespaces except network
2. **Bind Mounts**: Selectively mounts directories:
   - `/nix` (read-only) - Nix store access
   - Current directory (read-write) - Project files
   - Temp workspace (read-write) - Agent work directory
   - `/dev`, `/proc` (device access)
3. **Cleanup**: Trap ensures temp directory is removed on exit
4. **Die-with-parent**: Sandbox dies if wrapper process exits

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

### Why bubblewrap over alternatives?

- **No root required**: Works with user namespaces
- **Fine-grained control**: Selective bind mounts
- **Battle-tested**: Used by Flatpak
- **Lightweight**: Minimal overhead
- **Available in nixpkgs**: Easy integration

### Why not chroot?

Requires root/CAP_SYS_CHROOT and complex setup.

### Why not firejail?

Less flexible, opinionated defaults, larger attack surface.

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
