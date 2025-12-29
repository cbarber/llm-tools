# Agent API Authentication

Supplements `setup-agent-api-tokens.sh` script.

## Architecture

Agents use two separate authentication mechanisms:
- **Deploy keys (SSH)**: Git operations (push/pull)
- **API tokens**: PR/issue operations (create, comment, view)
- **Namespace**: `~/.config/nixsmith/`

Both are configured automatically on first shell entry.

## GitHub Token

**Requirements:**
- Token name: `nixsmith - {hostname}`
- Expiration: No expiration
- Repository access: All repositories (or select specific repos)
- Permissions:
  - Contents: Read
  - Pull requests: Read and write
  - Metadata: Read (auto-included)

**Storage:** `~/.config/nixsmith/github-token` (mode 600)

## Gitea Token

**Requirements:**
- Token name: `nixsmith - {hostname}`
- Scopes: `read:repository`, `write:issue`
- Note: Token grants access to all user repositories (Gitea limitation)

**Storage:** `~/.config/nixsmith/tea/config.yml` (via tea CLI)

## Manual Setup

If automatic setup fails:

**GitHub:**
1. Visit: https://github.com/settings/personal-access-tokens/new
2. Configure token as above
3. Store: `mkdir -p ~/.config/nixsmith && echo "TOKEN" > ~/.config/nixsmith/github-token && chmod 600 ~/.config/nixsmith/github-token`

**Gitea:**
1. Visit: {gitea-url}/user/settings/applications
2. Generate token with required scopes
3. Configure: `XDG_CONFIG_HOME=~/.config/nixsmith tea login add --name nixsmith --url {gitea-url} --token TOKEN`

## forge CLI Usage

**Tool:** `bash tools/forge` - Unified CLI wrapper that auto-detects GitHub vs Gitea from git remote.

### Creating a PR from Agent Work

**Complete workflow:**
```bash
# After completing work
git commit --fixup=abc123  # Fixup specific commit that needs changes
git push -u origin agent/llm-tools-xyz

# Create PR
bash tools/forge pr create \
  --title "Fix validation logic" \
  --body "Addresses feedback from previous review. See beads issue llm-tools-xyz"

# If tests failing
bash tools/forge pr create --draft \
  --title "WIP: Fix validation logic" \
  --body "Tests failing on line 42. Need guidance on edge case handling."
```

### PR Guidelines

**Draft PRs:**
- Use `--draft` when tests fail or work is incomplete
- Draft PRs document blockers and partial progress
- CI may not run on drafts (saves action minutes)

**PR Body:**
- Focus on WHY (motivation, rationale, context)
- Link to beads issue if applicable
- If draft: clearly state what's blocking completion
- Avoid itemizing implementation details

**Commit Hygiene:**
- Use `git commit --fixup=<sha>` when addressing review feedback
- Agent maintains atomic commits per the original work
- User handles final `git rebase --autosquash` if needed

**Approval:**
- Agents cannot approve their own PRs
- CI must pass before merge
- User provides final approval via: `bash tools/forge pr approve <number>`

### forge CLI Reference

**PR Operations:**
```bash
bash tools/forge pr create --title "..." --body "..." [--draft]
bash tools/forge pr view <number> [--comments] [--json]
bash tools/forge pr comment <number> "text"
bash tools/forge pr list [--state=open|closed] [--json]
bash tools/forge pr checkout <number>
bash tools/forge pr approve <number>
```

**Issue Operations:**
```bash
bash tools/forge issue list [--state=open|closed] [--json]
bash tools/forge issue show <number> [--json]
```

**Notes:**
- Auto-detects GitHub vs Gitea from git remote
- Normalizes flag differences (`--body` vs `--description`)
- JSON output format is forge-specific (not normalized)
- Requires `gh` (GitHub) or `tea` (Gitea) CLI to be available

## Troubleshooting

**forge authentication fails:**
- Verify token files exist and are readable (mode 600)
- Test GitHub: `GH_TOKEN=$(cat ~/.config/nixsmith/github-token) gh auth status`
- Test Gitea: `XDG_CONFIG_HOME=~/.config/nixsmith tea repos list`

**Token verification fails:**
- Ensure correct permissions were granted
- Recreate token with correct scopes
- For GitHub: Use fine-grained PAT, not classic PAT

**Permission errors:**
- Check file modes: `chmod 600 ~/.config/nixsmith/github-token`
- Check directory mode: `chmod 700 ~/.config/nixsmith`
