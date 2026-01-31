# Testing PR Approval Workflow

## How to Test the Rocket Approve Workflow

The workflow in `.github/workflows/approve-self.yaml` triggers on PR comments containing 🚀 or `:rocket:`.

### Test Scenarios

#### 1. **Test as Admin User (should approve)**
- Go to PR #70: https://github.com/cbarber/llm-tools/pull/70
- Post a comment: `🚀`
- Expected result:
  - PR gets approved
  - Comment gets a "hooray" reaction (🎉)
  - Check run shows success in Actions tab

#### 2. **Test with Leading Whitespace (should approve)**
- Post a comment: `  🚀` or `   :rocket:`
- Expected result: Same as scenario 1 (whitespace is trimmed)

#### 3. **Test as Non-Admin User (should ignore)**
- Have a non-admin collaborator comment `🚀` on the PR
- Expected result:
  - No approval occurs
  - No reaction added
  - No error message (silently ignored)
  - Workflow runs but skips approval steps

#### 4. **Test with Other Comment Text (should ignore)**
- Post a comment: `Ready to merge 🚀`
- Expected result: Workflow ignores (only exact match after trimming)

### Viewing Workflow Results

```bash
# View workflow runs for this PR
bash tools/forge pr checks 70

# View specific workflow run details
gh run view <run-id> --log
```

### Debug Information

Each workflow run logs:
- Comment body (exact match)
- Comment user
- Whether it's a PR
- PR number
- User's permission level (admin/write/read)
- Whether approval should happen

Access these logs via:
1. GitHub Actions tab
2. Find the "Rocket Approve PR" workflow run
3. Click "Debug info" step

### Manual Testing with `act` (Local)

You can test locally using [act](https://github.com/nektos/act):

```bash
# Install act (if not already installed)
nix-shell -p act

# Create test event payload
cat > /tmp/test-event.json <<'EOF'
{
  "action": "created",
  "issue": {
    "number": 70,
    "pull_request": {}
  },
  "comment": {
    "body": "🚀",
    "user": {
      "login": "cbarber"
    }
  },
  "repository": {
    "owner": {
      "login": "cbarber"
    },
    "name": "llm-tools"
  }
}
EOF

# Run workflow locally
act issue_comment -e /tmp/test-event.json -W .github/workflows/approve-self.yaml
```

Note: `act` may not perfectly replicate GitHub's environment, especially for permission checks.
