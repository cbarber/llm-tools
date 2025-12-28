# Agent SSH Keys Setup Guide

This guide explains how to set up SSH keys for agents to push/pull from git repositories securely.

## Why Deploy Keys?

**Problem with SSH Agent Confirmation:**
- Confirmation prompts lead to fatigue ("yes" becomes automatic)
- Agent could push malicious changes while you're on autopilot
- Similar to `sudo` fatigue - security theater

**Deploy Keys Solve This:**
- ✅ Agent can ONLY push to repos you explicitly grant access
- ✅ Can't accidentally push to your personal repositories
- ✅ Separate from your personal SSH keys
- ✅ Can be revoked per-repository without affecting others
- ✅ Shows "deployed via LLM Agent key" in audit logs
- ✅ No confirmation fatigue

## Quick Start

### 1. Generate Keys and Configure

```bash
# From project root (outside sandbox)
./tools/setup-agent-keys.sh
```

This script will:
1. Generate three SSH keys (if they don't exist):
   - `~/.ssh/agent-github` (for GitHub repositories)
   - `~/.ssh/agent-gitlab` (for GitLab repositories)
   - `~/.ssh/agent-gitea` (for Gitea repositories)

2. Create `~/.ssh/config.agent` with platform-specific key mapping

3. Update your `~/.ssh/config` to include the agent config

4. Update `agent-sandbox.sh` to mount agent keys (read-only)

5. Show instructions for adding the deploy key to your current repository

### 2. Add Deploy Key to Repository

The script will show you the public key and provide platform-specific instructions.

**GitHub:**
```bash
# Manual
1. Go to: https://github.com/owner/repo/settings/keys
2. Click "Add deploy key"
3. Title: LLM Agent
4. Key: (paste public key from setup script output)
5. ☑ Allow write access
6. Click "Add key"

# Or use GitHub CLI
gh repo deploy-key add ~/.ssh/agent-github.pub --title "LLM Agent" --allow-write
```

**GitLab:**
```bash
1. Go to: https://gitlab.com/owner/repo/-/settings/repository
2. Expand "Deploy Keys"
3. Title: LLM Agent
4. Key: (paste public key)
5. ☑ Write access allowed
6. Click "Add key"

# GitLab allows sharing deploy keys across projects in a group!
```

**Gitea:**
```bash
1. Go to repository settings → Deploy Keys
2. Title: LLM Agent
3. Key: (paste public key)
4. ☑ Allow write access (if available)
5. Click "Add key"
```

### 3. Test

```bash
# Try pushing from inside the agent sandbox
git push
```

If it fails, the error will tell you to run the setup script.

## How It Works

### SSH Key Selection

When git connects to a remote, SSH uses `~/.ssh/config` to determine which key to use:

```ssh
# ~/.ssh/config.agent
Host github.com
  IdentityFile ~/.ssh/agent-github
  IdentitiesOnly yes
```

- `IdentityFile`: Tells SSH which key to use for this host
- `IdentitiesOnly`: Don't try other keys, ONLY use this one

### In the Sandbox

The `agent-sandbox.sh` script bind mounts:
- `~/.ssh/agent-github` (read-only)
- `~/.ssh/agent-gitlab` (read-only)
- `~/.ssh/agent-gitea` (read-only)
- `~/.ssh/config.agent` → mounted AS `~/.ssh/config` (replaces your personal config)

**Important:** Inside the sandbox, `~/.ssh/config` IS the agent config. Your personal SSH config is NOT visible to the agent. This prevents:
- Exposure of personal SSH settings
- Conflicts with your host aliases
- Access to personal SSH keys
- Leaking internal server names or ProxyJump configurations

### What Agents Can Do

- ✅ Push/pull to repos where you've added the deploy key
- ✅ Clone public repositories
- ❌ Push to repos without deploy key configured
- ❌ Access your personal SSH keys
- ❌ Push to your personal repositories

## Per-Repository Setup

When you start working on a new repository:

1. **Enter the repository directory**
2. **Run setup script** (it auto-detects the current repo):
   ```bash
   cd ~/src/my-new-project
   ./path/to/tools/setup-agent-keys.sh
   ```

3. **Follow the instructions** to add the deploy key

Takes about 30 seconds per repository.

## Security Considerations

### Key Permissions

Deploy keys are repository-specific:
- ✅ Can read/write to that specific repository
- ❌ Cannot access other repositories
- ❌ Cannot access repository settings
- ❌ Cannot manage other deploy keys

### Revocation

If a key is compromised:
1. Go to repository settings → Deploy Keys
2. Delete "LLM Agent" key
3. Generate new key: `rm ~/.ssh/agent-* && ./tools/setup-agent-keys.sh`
4. Add new key to repositories

### Audit Trail

Deploy key usage appears in repository logs:
- Shows "pushed via deploy key: LLM Agent"
- Timestamp and commit details
- Different from your personal commits

## Troubleshooting

### "Permission denied (publickey)"

**Cause**: Deploy key not added to repository

**Fix**:
```bash
./tools/setup-agent-keys.sh
# Follow instructions to add deploy key
```

### "Key already exists but push fails"

**Cause**: Deploy key might not have write access enabled

**Fix**:
1. Go to repository settings → Deploy Keys
2. Find "LLM Agent"
3. Ensure "Allow write access" is checked

### "Multiple keys for same host"

**Cause**: Your `~/.ssh/config` might have conflicting entries

**Fix**:
Ensure agent config is included FIRST in `~/.ssh/config`:
```ssh
Include config.agent  # This line should be at the top

# Your other config below...
```

### SSH Config Not Included

If setup script says config not included, manually add to top of `~/.ssh/config`:
```bash
echo "Include config.agent" | cat - ~/.ssh/config > /tmp/config && mv /tmp/config ~/.ssh/config
```

## Advanced Usage

### Sharing Keys Across Repositories (GitLab)

GitLab allows deploy keys to be shared across projects in a group:

1. Add deploy key to one project in the group
2. Go to group settings → Repository → Deploy Keys
3. Enable the key for the entire group
4. All projects in group can now use it

### Multiple Gitea Instances

If you use multiple Gitea servers, create separate keys:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agent-gitea-company -C "agent@company-gitea"
ssh-keygen -t ed25519 -f ~/.ssh/agent-gitea-personal -C "agent@personal-gitea"
```

Update `~/.ssh/config.agent`:
```ssh
Host company.gitea.io
  IdentityFile ~/.ssh/agent-gitea-company
  IdentitiesOnly yes

Host personal.gitea.io
  IdentityFile ~/.ssh/agent-gitea-personal
  IdentitiesOnly yes
```

## FAQ

**Q: Do I need to run setup script for every repository?**

A: You only need to generate keys once. For each new repository, you just need to add the deploy key via the web UI (30 seconds).

**Q: Can agents push to any branch?**

A: Deploy keys grant repository-level access. Branch protection rules still apply - if main is protected, the agent can't force push to it.

**Q: What if I want agents to use different keys per project?**

A: You can create project-specific keys and update `~/.ssh/config.agent` to use them based on the repository URL.

**Q: Do these keys expire?**

A: No, but you can rotate them anytime by regenerating and re-adding to repositories.

**Q: Can I use the same key for multiple repositories?**

A: Yes, but you need to add it as a deploy key to each repository separately (except GitLab groups which support sharing).

**Q: What happens to my personal SSH config?**

A: Your personal `~/.ssh/config` is NOT mounted in the sandbox. The agent only sees `~/.ssh/config.agent` (mounted as `~/.ssh/config`). This keeps your personal SSH settings, ProxyJumps, and host aliases completely private.

**Q: Will the agent config conflict with my personal config?**

A: No, they're completely separate. Outside the sandbox you use your personal config. Inside the sandbox, only the agent config is visible.
