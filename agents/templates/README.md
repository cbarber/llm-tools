# Agent Templates

This directory contains workflow instruction files injected ephemerally into agent sessions.

## How It Works

On shell entry, the resolved workflow file is written to a per-session temp file and
injected into the agent — never written to the project repo. Project `AGENTS.md` files
are entirely the project's concern.

## Workflow File Selection

Priority (first match wins):

1. `$AGENTS_TEMPLATE` env var — set before shell entry for per-shell override
   - Relative paths resolve against `$AGENTS_TEMPLATES_DIR` (this directory in the Nix store)
   - Absolute paths used as-is
2. `~/.config/nixsmith/workflow.md` — personal workflow, applies to all projects
3. `agents/templates/workflow.md` — default fallback

## Customising Your Workflow

Drop your workflow file at `~/.config/nixsmith/workflow.md`. It will be picked up
automatically on every shell entry across all projects, with no repo changes needed.

To diff against the upstream default:

```bash
diff ~/.config/nixsmith/workflow.md "$AGENTS_TEMPLATES_DIR/workflow.md"
```

## Parallel Shell Experimentation

Override per shell before entering the environment:

```bash
AGENTS_TEMPLATE=my-experiment.md nix develop .#opencode
```

Relative names resolve against `$AGENTS_TEMPLATES_DIR`. Each shell gets its own
temp file so parallel shells in the same worktree don't interfere.
