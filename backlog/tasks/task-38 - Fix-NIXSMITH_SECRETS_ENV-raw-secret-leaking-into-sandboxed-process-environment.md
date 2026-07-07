---
id: TASK-38
title: Fix NIXSMITH_SECRETS_ENV raw secret leaking into sandboxed process environment
status: In Progress
assignee: []
created_date: '2026-07-02 17:06'
labels: []
dependencies: []
priority: high
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
agent-sandbox.sh passes --allow-env to zerobox, which forwards the entire outer shell environment into the sandbox unfiltered. setup-sandbox-paths.sh exports NIXSMITH_SECRETS_ENV as a plaintext key=value list of real secrets (e.g. GH_TOKEN=github_pat_...) so agent-sandbox.sh can build --secret flags for zerobox. Because that variable is exported and --allow-env is used, the raw secret values leak straight into the sandboxed process's own environment via /proc/<pid>/environ, even though zerobox correctly substitutes a ZEROBOX_SECRET_ placeholder for the named var (e.g. GH_TOKEN) itself. Verified experimentally: cat /proc/$$/environ inside an active opencode sandbox session showed GH_TOKEN as the placeholder, but NIXSMITH_SECRETS_ENV contained the real github_pat_... token in plaintext. diagnose-zerobox-secret.sh does not catch this because it only checks substitution of a single synthetic --secret var, not whether the control-plane NIXSMITH_SECRETS_ENV/NIXSMITH_SECRETS_HOSTS variables themselves are visible inside the sandbox. Fix: unset NIXSMITH_SECRETS_ENV (and audit NIXSMITH_SECRETS_HOSTS, which currently only holds host lists not secret values) before exec'ing zerobox in tools/agent-sandbox.sh, or stop using --allow-env wholesale and instead pass through only an explicit allowlist of non-secret vars. Add a regression check to diagnose-zerobox-secret.sh that greps /proc/self/environ inside the sandbox for real secret values, not just the named placeholder var.
<!-- SECTION:DESCRIPTION:END -->
