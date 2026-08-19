---
description: Use agent-zsh for local shell execution; keep Fish as login shell
alwaysApply: true
---

# Agent shell policy

User login shell is **Fish** and must remain Fish.

When running shell/exec commands on this macOS host:

1. Primary: `agent-zsh -c '<command>'`
2. Fallback: `agent-bash -c '<command>'`
3. Diagnostics: `agent-term-doctor` or `agent-session`

Do not emit raw Fish syntax.
Do not change the macOS login shell.
Prefer non-interactive-safe env: `PYTHONUNBUFFERED=1`, `PAGER=cat`, `GIT_PAGER=cat`.

Cloud/Devin VM environments do not automatically include `~/bin/agent-zsh`; only use these launchers on the local machine (or after installing equivalents remotely).
