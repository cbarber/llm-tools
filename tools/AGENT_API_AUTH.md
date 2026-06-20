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

GitHub fine-grained PATs are stored in `secrets.json` under the `repos` key,
keyed by `github:<owner>` (org or username, always lowercased).

**Token name on GitHub:** `nixsmith - <hostname> - <owner>`

**Requirements:**

- Expiration: No expiration
- Repository access: Repositories owned by `<owner>`
- Permissions:
  - Contents: Read and write
  - Pull requests: Read and write
  - Metadata: Read (auto-included)

**Caveat:** Pushing changes to `.github/workflows/` requires the `Workflows`
permission. Add it only if the agent needs to modify CI configuration.

**Setup:** run `tools/setup-agent-api-tokens.sh` — it opens the GitHub token
creation page, verifies the token, and writes it into `secrets.json`.

The token is injected into the sandbox as `GH_TOKEN` via `--setenv` and used
by `git-credential-nixsmith` for HTTPS git operations. It is never written into
the session gitconfig or any temp file.

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
sandbox mount lists (`NIXSMITH_SANDBOX_RO`/`NIXSMITH_SANDBOX_RW`), and filesystem
probes — all with `OK`/`WARN`/`FAIL` prefixes.

### Creating a PR from Agent Work

**Complete workflow:**

```bash
# After completing work
git push -u origin agent/llm-tools-xyz

# Create PR
forge pr create \
  --title "Fix validation logic" \
  --body "Addresses feedback from previous review.: Fix validation logic" \
  --body "Tests failing on line 42. Need guidance on edge case handling."
```

### PR Guidelines

**Draft PRs:**

- Use `--draft` when tests fail or work is incomplete
- Draft PRs document blockers and partial progress
- CI may not run on drafts (saves action minutes)

**PR Body:**

- Focus on WHY (motivation, rationale, context)
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

- Test Gitea: `XDG_CONFIG_HOME=~/.config/nixsmith tea repos list`

**Token verification fails:**

- Ensure correct permissions were granted
- Recreate token with correct scopes
- For GitHub: Use fine-grained PAT, not classic PAT

**Permission errors:**

- Check directory mode: `chmod 700 ~/.config/nixsmith`

## LLM API Keys

LLM provider credentials are injected into the sandbox via
`~/.config/nixsmith/secrets.json`. They are never sourced into the outer shell.

**File:** `~/.config/nixsmith/secrets.json` (mode `600`)

**Format:**

```json
{
  "repos": {
    "github:acmecorp": {
      "ANTHROPIC_API_KEY": "sk-ant-work-...",
      "GH_TOKEN": "ghp_..."
    }
  },
  "paths": {
    "/home/alice/src/work-project": {
      "ANTHROPIC_API_KEY": "sk-ant-work-..."
    },
    "/home/alice/src": {
      "ANTHROPIC_API_KEY": "sk-ant-personal-..."
    }
  }
}
```

**Matching:** `repos` match (derived from the git remote owner) wins over
`paths`. Under `paths`, the longest prefix of `pwd` wins.

**Injection:** at sandbox launch, matched vars are passed to bwrap as individual
`--setenv` arguments and are never assigned to outer shell variables.

**Supported variables** (non-exhaustive):

| Provider | Variable |
| --- | --- |
| Anthropic | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| Google Vertex | `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT` |
| AWS Bedrock | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BEARER_TOKEN_BEDROCK` |
| Azure OpenAI | `AZURE_OPENAI_API_KEY`, `AZURE_RESOURCE_NAME` |
| GitHub | `GITHUB_TOKEN` |
| GitLab | `GITLAB_TOKEN` |
| Groq | `GROQ_API_KEY` |
| Mistral | `MISTRAL_API_KEY` |
| xAI | `XAI_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| NVIDIA | `NVIDIA_API_KEY` |
| DigitalOcean | `DIGITALOCEAN_ACCESS_TOKEN` |

Any key in the matched object is injected — the list above is guidance, not a
restriction.

**Setup:**

```bash
mkdir -p ~/.config/nixsmith
# create/edit the file
chmod 600 ~/.config/nixsmith/secrets.json
```

Run `forge doctor` to verify the file is found, permissions are correct, and a
pattern matches the current project.

### Agent credential file isolation

OpenCode stores credentials in `~/.local/share/opencode/auth.json`, which
is mounted into the sandbox for legitimate reasons (session history, MCP
OAuth tokens). To prevent stored credentials leaking across projects,
`OPENCODE_AUTH_CONTENT` is set to an empty JSON object.

### Outer shell isolation

After sourcing `.env` files, `setup-shared-shell.sh` unsets all known AI
provider credentials from the outer shell. This prevents credentials set in
`.env` or the environment from leaking into the sandbox via shell inheritance.
Credentials reach the sandbox exclusively through secrets.json `--setenv`
injection.

The blocklist covers: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
`CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK/VERTEX/FOUNDRY`,
`OPENAI_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`,
`AWS_BEARER_TOKEN_BEDROCK`, `AZURE_OPENAI_API_KEY`, `AZURE_RESOURCE_NAME`,
`GITLAB_TOKEN`, `CLOUDFLARE_API_TOKEN`, `NVIDIA_API_KEY`,
`DIGITALOCEAN_ACCESS_TOKEN`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `XAI_API_KEY`,
`OPENROUTER_API_KEY`.

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
