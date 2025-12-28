# Agent Templates

This directory contains templates for agent instruction files (AGENTS.md/CLAUDE.md).

## Template Selection

Templates are selected based on the `$USER` environment variable:

1. **User-specific**: `${USER}.md` (e.g., `cbarber.md`)
2. **Default**: `default.md` (fallback for all users)

## Creating a User-Specific Template

To create your own personalized template:

```bash
# Copy the default template as a starting point
cp agents/templates/default.md agents/templates/${USER}.md

# Edit to add your preferences
# Example customizations:
# - Personal coding style preferences
# - Project-specific guidelines
# - Team conventions
# - Frequently used commands
```

## Example

If your username is `cbarber`, create `agents/templates/cbarber.md`:

```bash
cp agents/templates/default.md agents/templates/cbarber.md
# Edit agents/templates/cbarber.md with your preferences
```

Next time you run `nix develop .#claude-code` or `nix develop .#opencode`, your custom template will be used automatically when creating new AGENTS.md files.

## Template Structure

Templates should include:
- **Development Guidelines**: Coding style, naming conventions
- **Landing the Plane**: Session completion checklist
- **Project-specific instructions**: Add any project context here

See `default.md` for the recommended baseline structure.
