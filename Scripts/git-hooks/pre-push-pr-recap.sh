#!/usr/bin/env bash
# Git pre-push hook for Agent-Native PR Recap
# Validates issue keys on current branch/commits and runs local pre-push sync.
set -euo pipefail

# Bypass options:
# 1. git push --no-verify  (native git flag)
# 2. PR_RECAP_SKIP=1 git push
# 3. SKIP_PR_RECAP=1 git push
if [[ ${PR_RECAP_SKIP:-0} == "1" ]] || [[ ${SKIP_PR_RECAP:-0} == "1" ]]; then
	exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${HOOK_DIR}/../.." ]]; then
	REPO_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"
else
	REPO_ROOT="$(pwd)"
fi

# Discover pr-recap executable
RECAP_BIN=""
if [[ -x "${REPO_ROOT}/pr-recap" ]]; then
	RECAP_BIN="${REPO_ROOT}/pr-recap"
elif [[ -x "${REPO_ROOT}/scripts/pr-recap" ]]; then
	RECAP_BIN="${REPO_ROOT}/scripts/pr-recap"
elif command -v pr-recap >/dev/null 2>&1; then
	RECAP_BIN="$(command -v pr-recap)"
elif [[ -x "${HOME}/bin/pr-recap" ]]; then
	RECAP_BIN="${HOME}/bin/pr-recap"
elif [[ -x "${HOME}/.local/bin/pr-recap" ]]; then
	RECAP_BIN="${HOME}/.local/bin/pr-recap"
elif [[ -x "${HOME}/.gemini/antigravity-cli/bin/pr-recap" ]]; then
	RECAP_BIN="${HOME}/.gemini/antigravity-cli/bin/pr-recap"
elif [[ -x "/Users/speedybee/dev/personal-config/scripts/pr-recap" ]]; then
	RECAP_BIN="/Users/speedybee/dev/personal-config/scripts/pr-recap"
fi

if [[ -z ${RECAP_BIN} ]] || [[ ! -x ${RECAP_BIN} ]]; then
	exit 0
fi

# Limit secret resolution timeout in git hook to 8 seconds for desktop biometrics/IPC
export PR_RECAP_KEY_TIMEOUT="${PR_RECAP_KEY_TIMEOUT:-8.0}"

# Run pre-push sync.
# If credentials cannot be unlocked or resolved, fail non-blockingly unless STRICT_PR_RECAP=1
if ! "${RECAP_BIN}" sync --pre-push; then
	if [[ ${STRICT_PR_RECAP:-0} == "1" ]]; then
		echo "[pr-recap] ERROR: Pre-push PR recap sync failed and STRICT_PR_RECAP=1 is set. Aborting push." >&2
		exit 1
	else
		echo "[pr-recap] NOTE: Pre-push sync could not complete (vault locked, CLI unavailable, or offline). Push continuing." >&2
		echo "[pr-recap] To test sync manually: pr-recap sync --dry-run" >&2
		exit 0
	fi
fi
