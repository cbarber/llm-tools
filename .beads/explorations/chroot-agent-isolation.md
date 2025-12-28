# Agent Isolation with Sandboxing

## Goal

Constrain CLI agents (Claude Code, OpenCode) on startup to prevent access outside project scope while maintaining necessary tool access.

## Requirements

1. **Temporary workspace**: Provide /tmp access, use mktemp for agent work directory
2. **Cleanup**: Remove work directory on exit (no symlink following)
3. **Tool access**: git, editors, shell utilities must remain functional
4. **No root required**: Solution should work for unprivileged users

## Options Evaluated

### 1. chroot (Traditional)

**Pros:**
- Simple concept: changes root directory
- Well-understood Unix primitive

**Cons:**
- **Requires root/CAP_SYS_CHROOT**: Not suitable for unprivileged users
- Complex setup: need to populate chroot with all dependencies
- Hard to maintain: must replicate system tools, libraries

**Verdict:** ❌ Not practical for user-level agent isolation

### 2. Bubblewrap (bwrap)

**Pros:**
- **No root required**: Uses user namespaces
- Fine-grained control: bind mount specific directories
- Designed for sandboxing: Used by Flatpak
- Available in nixpkgs: `pkgs.bubblewrap`

**Cons:**
- Requires user namespace support (typically available on modern Linux)
- More complex CLI than chroot

**Example:**
```bash
bwrap \
  --ro-bind /nix /nix \
  --bind "$(pwd)" "$(pwd)" \
  --bind /tmp /tmp \
  --dev /dev \
  --proc /proc \
  --unshare-all \
  --share-net \
  claude
```

**Verdict:** ✅ Best option for unprivileged sandboxing

### 3. firejail

**Pros:**
- User-friendly profiles
- Good for desktop applications
- Extensive security features

**Cons:**
- Opinionated defaults may conflict with agent needs
- Less fine-grained control than bubblewrap
- Larger attack surface

**Verdict:** ⚠️ Possible but less flexible

### 4. unshare + mount namespaces

**Pros:**
- Linux kernel feature
- Fine-grained namespace isolation

**Cons:**
- Requires CAP_SYS_ADMIN or user namespaces
- Lower-level than bubblewrap (more setup code)

**Verdict:** ⚠️ Bubblewrap wraps this nicely

## Recommended Approach: Bubblewrap

### Implementation Plan

1. **Add bubblewrap to shell environments**
   ```nix
   buildInputs = [
     pkgs.bubblewrap
     # ... existing tools
   ];
   ```

2. **Create wrapper script** (`tools/agent-sandbox.sh`)
   ```bash
   #!/usr/bin/env bash
   # Usage: agent-sandbox <command> [args...]
   
   WORK_DIR=$(mktemp -d -t agent-XXXXXX)
   trap "rm -rf '$WORK_DIR'" EXIT
   
   bwrap \
     --ro-bind /nix /nix \
     --bind "$(pwd)" "$(pwd)" \
     --bind "$WORK_DIR" /tmp/agent-work \
     --dev-bind /dev /dev \
     --proc /proc \
     --tmpfs /tmp \
     --unshare-all \
     --share-net \
     --die-with-parent \
     "$@"
   ```

3. **Integrate with agent shells**
   - Option A: Wrapper command `agent-sandbox claude`
   - Option B: Environment variable `AGENT_SANDBOX=true`
   - Option C: Always-on (may break some workflows)

### Trade-offs

**Pros:**
- Prevents accidental access to $HOME, /etc, other projects
- Temporary workspace cleanup guaranteed
- No root required
- Works with existing Nix setup

**Cons:**
- User namespace support required (usually available)
- May break workflows expecting full filesystem access
- Slight performance overhead (minimal)
- Debugging may be harder inside sandbox

## Open Questions

1. **Should sandboxing be opt-in or opt-out?**
   - Opt-in: `AGENT_SANDBOX=true nix develop .#claude-code`
   - Opt-out: `AGENT_SANDBOX=false nix develop .#claude-code` (default on)

2. **What directories need bind mounts?**
   - `/nix` (read-only): Essential for Nix store
   - Current project directory (read-write)
   - `/tmp` or custom temp dir (read-write)
   - `/dev`, `/proc` (device/process access)
   - Git config? SSH keys? (may break git operations)

3. **How to handle git authentication?**
   - SSH keys in `~/.ssh` won't be accessible
   - Options: bind mount `~/.ssh` (read-only), use credential helpers

4. **Should we support breaking out of sandbox?**
   - Escape hatch for power users
   - Could use `AGENT_SANDBOX=false` env var

## Next Steps

1. ✅ Document research findings (this file)
2. ⬜ Prototype bubblewrap wrapper script
3. ⬜ Test with Claude Code in sandboxed environment
4. ⬜ Measure performance impact
5. ⬜ Decide on opt-in vs opt-out default
6. ⬜ Implement in agent shells if viable
7. ⬜ Document usage and limitations

## References

- [Bubblewrap documentation](https://github.com/containers/bubblewrap)
- [Flatpak sandboxing](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
- [Linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html)
