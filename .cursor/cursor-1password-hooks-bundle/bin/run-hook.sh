#!/bin/bash

set -euo pipefail

# Entry point for all IDE hook invocations.
# Usage: bin/run-hook.sh <hook-name>
#
# Reads raw IDE JSON from stdin, detects the calling IDE, normalizes input
# through the matching adapter, runs the hook, and translates the output
# back to the IDE's expected format.
#
# Fails open on any error — emits the IDE's "allow" response and exits cleanly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/json.sh"
source "${REPO_ROOT}/lib/telemetry.sh"

# Read hook version from VERSION file
HOOK_VERSION=""
if [[ -f "${REPO_ROOT}/VERSION" ]]; then
	HOOK_VERSION=$(head -n1 "${REPO_ROOT}/VERSION" 2>/dev/null || echo "")
fi

HOOK_NAME="${1-}"
if [[ -z $HOOK_NAME ]]; then
	log "Error: no hook name provided to run-hook.sh"
	exit 0
fi

if [[ $HOOK_NAME == */* ]] || [[ $HOOK_NAME == *..* ]]; then
	log "Error: invalid hook name '${HOOK_NAME}' — must not contain '/' or '..'"
	exit 0
fi

HOOK_SCRIPT="${REPO_ROOT}/hooks/${HOOK_NAME}/hook.sh"
if [[ ! -f $HOOK_SCRIPT ]]; then
	log "Error: hook script not found: ${HOOK_SCRIPT}"
	exit 0
fi

LOG_TAG="run-hook:${HOOK_NAME}"

# ── 1. Buffer raw payload ────────────────────────────────────────────────
raw_payload=$(cat)

if [[ -z $raw_payload ]]; then
	log "Warning: empty payload on stdin, failing open"
	exit 0
fi

# ── 2. Detect client ─────────────────────────────────────────────────────
# Centralized detection in adapters/_lib.sh uses env vars + payload fields
# in most-specific-first order to avoid ambiguity.
ADAPTERS_DIR="${REPO_ROOT}/adapters"
source "${ADAPTERS_DIR}/_lib.sh"

detected_client=$(detect_client "$raw_payload")

# Map "unknown" to the generic fallback adapter
detected_adapter="$detected_client"
if [[ $detected_adapter == "unknown" ]]; then
	detected_adapter="generic"
fi

log "Detected client: ${detected_adapter}"

# ── 3. Source matching adapter ───────────────────────────────────────────
adapter_file="${ADAPTERS_DIR}/${detected_adapter}.sh"
if [[ ! -f $adapter_file ]]; then
	log "Error: adapter file not found: ${adapter_file}, failing open"
	exit 0
fi
source "$adapter_file"

# ── 4. Normalize input ──────────────────────────────────────────────────
canonical_input=$(normalize_input "$raw_payload") || {
	log "Error: normalize_input failed, failing open"
	exit 0
}

if [[ -z $canonical_input ]]; then
	log "Error: normalize_input produced empty output, failing open"
	exit 0
fi

canonical_event=$(extract_json_string "$canonical_input" "event")
log "Canonical event: ${canonical_event}"

# ── 5. Pipe to hook ─────────────────────────────────────────────────────
start_ms=$(current_time_ms)

canonical_output=$(echo "$canonical_input" | bash "$HOOK_SCRIPT" 2>/dev/null) || true

end_ms=$(current_time_ms)
duration_ms=$((end_ms - start_ms))

if [[ -z $canonical_output ]]; then
	log "Warning: hook produced no output, failing open"
	canonical_output='{"decision":"allow","message":""}'
fi

# ── 6–7. Log telemetry ──────────────────────────────────────────────────
decision=$(extract_json_string "$canonical_output" "decision")
if [[ -z $decision ]]; then
	log "Warning: could not extract decision from hook output, failing open"
	canonical_output='{"decision":"allow","message":""}'
	decision="allow"
fi

log "Hook result: decision=${decision} duration_ms=${duration_ms}"

# ── 7. Emit client-specific output ──────────────────────────────────────────
# Capture the exit code so we can run telemetry afterwards (off the hot path)
# and still exit with the IDE-facing status. claude-code's emit_output returns
# 2 on deny; under `set -e` this would otherwise terminate the script before
# telemetry runs.
emit_status=0
emit_output "$canonical_output" || emit_status=$?

# ── 8. Write telemetry event in a detached background subshell ──────────────
# The IDE waits for the whole process to exit. Backgrounding with
# `&` lets the script exit immediately while the telemetry write completes
# asynchronously.
#
# The `>/dev/null 2>&1` redirect is critical: without it, the subshell
# inherits the script's stdout/stderr pipes to the IDE, and the IDE's read
# of stdout would block until the subshell also closes its dup of the fd —
# defeating the purpose of backgrounding.
(
	hook_mode=$(extract_json_string "$canonical_output" "mode")
	hook_mount_count=$(extract_json_integer "$canonical_output" "mount_count")
	hook_deny_reason=$(extract_json_string "$canonical_output" "deny_reason")

	# mode / mount_count are validate_mounted_env_files-specific. Hooks that
	# do not populate them leave the values empty here, and write_execution_event
	# serializes empty as JSON null per the schema.

	write_execution_event \
		"$HOOK_NAME" \
		"$HOOK_VERSION" \
		"$detected_client" \
		"$canonical_event" \
		"$decision" \
		"$hook_deny_reason" \
		"$duration_ms" \
		"$hook_mode" \
		"$hook_mount_count"

	# Install events are only emitted from this layer for manually-copied
	# bundles. install.sh emits its own install_script events directly, and
	# plugin distributions (Cursor marketplace, etc.) are responsible for
	# emitting their own. The sentinel inside the helper exists purely to
	# keep run-hook.sh from re-emitting the manual event on every hook
	# invocation.
	install_method=$(detect_install_method "$SCRIPT_DIR")
	if [[ $install_method == "manual" ]]; then
		emit_manual_install_event_once "$detected_client" "$HOOK_NAME" "$HOOK_VERSION"
	fi
) >/dev/null 2>&1 &

exit "$emit_status"
