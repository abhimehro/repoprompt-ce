#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

allowlist="${CONTRIBUTOR_ALLOWLIST_FILE:-.github/APPROVED_CONTRIBUTORS}"
if [[ ! -f "$allowlist" ]]; then
  printf 'ERROR: contributor allowlist is missing: %s\n' "$allowlist" >&2
  exit 1
fi

failures=0
entry_count=0
previous_key=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  failures=$((failures + 1))
}

line_number=0
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_number=$((line_number + 1))
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ -z "$line" || "$line" == \#* ]]; then
    continue
  fi

  read -r -a parts <<< "$line"
  if [[ "${#parts[@]}" -ne 2 ]]; then
    fail "$allowlist:$line_number must use '<username> <capability>'"
    continue
  fi

  username="${parts[0]}"
  capability="${parts[1]}"
  if [[ ! "$username" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]; then
    fail "$allowlist:$line_number has invalid GitHub username '$username'"
  fi
  if [[ "$capability" != "issue" && "$capability" != "pr" ]]; then
    fail "$allowlist:$line_number has invalid capability '$capability'"
  fi

  key="$(printf '%s' "$username" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$previous_key" && "$key" == "$previous_key" ]]; then
    fail "$allowlist:$line_number duplicates '$username' case-insensitively"
  elif [[ -n "$previous_key" && "$key" < "$previous_key" ]]; then
    fail "$allowlist:$line_number is out of case-insensitive sort order: '$username'"
  fi
  previous_key="$key"
  entry_count=$((entry_count + 1))
done < "$allowlist"

if [[ "$entry_count" -eq 0 ]]; then
  fail "$allowlist contains no contributor entries"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'Contributor allowlist guardrails failed (%s issue%s).\n' \
    "$failures" "$([[ "$failures" == 1 ]] && printf '' || printf 's')" >&2
  exit 1
fi

printf 'OK: contributor allowlist guardrails passed (%s entries).\n' "$entry_count"
