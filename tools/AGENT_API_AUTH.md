# Agent API Authentication

Supplements `setup-agent-api-tokens.sh` script.

## Architecture

Agents use two separate authentication mechanisms:

- **Fine-grained PAT**: Git operations (push/pull/fetch) for GitHub, and PR/issue operations
- **Deploy keys (SSH)**: Git operations for non-GitHub hosts (GitLab, Gitea)
- **Namespace**: `~/.config/nixsmith/`

Both are configured automatically on first shell entry. Inside the sandbox, the PAT is
injected as a git credential helper so all GitHub remotes use HTTPS regardless of how
the repo was cloned or what URL rewrites exist in the host gitconfig.

## GitHub Token

GitHub fine-grained PATs are scoped to a single organization. Tokens are stored
**per owner** (org or username) so the agent can work across multiple GitHub organizations
without conflicting credentials.

**Token file naming:** `~/.config/nixsmith/github-token-<owner>`

- `<owner>` is the GitHub org or username, always **lowercased**
- GitHub names are case-insensitive; lowercasing avoids case-collision on Linux filesystems
- Examples: `github-token-acmecorp`, `github-token-cbarber`

**Token name on GitHub:** `nixsmith - <hostname> - <owner>`

Naming the PAT with the owner makes it unambiguous when managing multiple tokens in the
GitHub settings UI.

**Requirements:**

- Expiration: No expiration
- Repository access: Repositories owned by `<owner>`
- Permissions:
  - Contents: Read and write
  - Pull requests: Read and write
  - Metadata: Read (auto-included)

**Caveat:** Pushing changes to `.github/workflows/` requires the `Workflows`
permission. Add it only if the agent needs to modify CI configuration.

**Security note:** The token is read from disk at each git operation by
`git-credential-nixsmith` via the `GITHUB_TOKEN_FILE` env var set at sandbox launch.
It is never written into the session gitconfig or any temp file. However, a compromised
agent process with sandbox access to `~/.config/nixsmith/` could read the token directly
— scope it to only the repositories and permissions the agent actually needs.

### Migration from single-token setup

If you have an existing `~/.config/nixsmith/github-token` file, shell entry will be
blocked with a migration command. Run it and re-enter the shell:

```bash
mv ~/.config/nixsmith/github-token \
   ~/.config/nixsmith/github-token-<owner>
```

Replace `<owner>` with your GitHub username or org name (lowercase).

### Manual setup

```bash
mkdir -p ~/.config/nixsmith
echo "TOKEN" > ~/.config/nixsmith/github-token-<owner>
chmod 600 ~/.config/nixsmith/github-token-<owner>
```

## Gitea Token

**Requirements:**

- Token name: `nixsmith - {hostname}`
- Scopes: `read:repository`, `write:issue`
- Note: Token grants access to all user repositories (Gitea limitation)

**Storage:** `~/.config/nixsmith/tea/config.yml` (via tea CLI)

**Gitea:**

1. Visit: {gitea-url}/user/settings/applications
2. Generate token with required scopes
3. Configure: `XDG_CONFIG_HOME=~/.config/nixsmith tea login add --name nixsmith --url {gitea-url} --token TOKEN`

## forge CLI Usage

**Tool:** `forge` - Unified CLI wrapper that auto-detects GitHub vs Gitea from git remote.

### Health check

Before debugging auth failures, run:

```bash
forge doctor
```

Reports: git state, token file presence, live `gh auth status`, required tools in PATH,
sandbox mount lists (`NIXSMITH_SANDBOX_RO`/`NIXSMITH_SANDBOX_RW`), filesystem probes,
and beads stats — all with `OK`/`WARN`/`FAIL` prefixes.

### Creating a PR from Agent Work

**Complete workflow:**

```bash
# After completing work
git push -u origin agent/llm-tools-xyz

# Create PR
forge pr create \
  --title "Fix validation logic" \
  --body "Addresses feedback from previous review. See beads issue llm-tools-xyz"

# If tests failing
forge pr create --draft \
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
- User provides final approval via: `forge pr approve <number>`

### forge CLI Reference

**Diagnostics:**

```bash
forge doctor                  # Sandbox health check
```

**PR Operations:**

```bash
forge pr create --title "..." --body "..." [--draft]
forge pr view <number> [--comments] [--json]
forge pr comment <number> "text"
forge pr list [--state=open|closed] [--json]
forge pr checkout <number>
forge pr approve <number>
```

**Issue Operations:**

```bash
forge issue list [--state=open|closed] [--json]
forge issue show <number> [--json]
```

**Notes:**

- Auto-detects GitHub vs Gitea from git remote
- Normalizes flag differences (`--body` vs `--description`)
- JSON output format is forge-specific (not normalized)
- Requires `gh` (GitHub) or `tea` (Gitea) CLI to be available

## Troubleshooting

**forge authentication fails:**

```bash
forge doctor          # Start here — shows token file path and live auth status
```

- Verify token file exists and is readable (mode 600)
- Test manually: `GH_TOKEN=$(cat ~/.config/nixsmith/github-token-<owner>) gh auth status`
- Test Gitea: `XDG_CONFIG_HOME=~/.config/nixsmith tea repos list`

**Token verification fails:**

- Ensure correct permissions were granted
- Recreate token with correct scopes
- For GitHub: Use fine-grained PAT, not classic PAT

**Permission errors:**

- Check file modes: `chmod 600 ~/.config/nixsmith/github-token-<owner>`
- Check directory mode: `chmod 700 ~/.config/nixsmith`

## Reviewing LLM Commits

During `git rebase -i`, stamp each reviewed commit with a `Reviewed-By` trailer
to mark it as human-verified. `pr-poll` removes the draft state and
`needs-human-review` label automatically once all `Authored-By` commits are stamped.

Add this to your Neovim config to insert the trailer from the current git identity:

```lua
vim.keymap.set('n', '<leader>rv', function()
  local name = vim.fn.system('git config user.name'):gsub('\n', '')
  local email = vim.fn.system('git config user.email'):gsub('\n', '')
  local trailer = 'Reviewed-By: ' .. name .. ' <' .. email .. '>'
  vim.api.nvim_put({ trailer }, 'l', true, true)
end, { desc = 'Insert Reviewed-By trailer' })
```

Use it while editing a commit message buffer during `git rebase -i --edit`.
