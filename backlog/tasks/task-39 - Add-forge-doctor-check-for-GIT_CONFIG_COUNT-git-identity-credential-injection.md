---
id: TASK-39
title: Add forge doctor check for GIT_CONFIG_COUNT git identity/credential injection
status: Done
assignee: []
created_date: '2026-07-14 15:52'
updated_date: '2026-07-30 12:56'
labels: []
dependencies: []
modified_files:
  - tools/forge
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
setup-sandbox-paths.sh now injects url.insteadOf, credential.helper, and allowlisted user.name/user.email/push.*/init.defaultBranch via GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n (replacing the old synthetic gitconfig file). forge doctor has no check that these env vars are actually present/correct inside a sandboxed session, or that git-credential-nixsmith is resolvable and returns credentials when GH_TOKEN is set. Add a doctor check for this so a broken nix rebuild or misconfigured PATH is caught early (this was previously masked by an undefined $token typo in git-credential-nixsmith that silently broke all pushes).
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
forge doctor now validates effective Git identity, current-origin HTTPS resolution, and credential-helper behavior through the Git CLI, only when run inside a Git repository.
<!-- SECTION:FINAL_SUMMARY:END -->
