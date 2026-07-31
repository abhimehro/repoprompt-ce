#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:-}"
EXPECTED_COMMIT="${2:-}"
GIT_ROOT="${REPOPROMPT_GIT_ROOT:-.}"
REQUIRE_HEAD_MATCH="${REPOPROMPT_REQUIRE_HEAD_MATCH:-1}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -n "$RELEASE_TAG" && -n "$EXPECTED_COMMIT" ]] ||
    fail "Usage: $0 <release-tag> <expected-commit>"
[[ "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    fail "Release tag must use canonical v<major>.<minor>.<patch> form: $RELEASE_TAG"

if [[ -n "${SOURCE_GITHUB_REPOSITORY:-}" && -n "${SOURCE_GH_TOKEN:-${GH_TOKEN:-}}" ]]; then
    command -v gh >/dev/null 2>&1 || fail "Missing required command: gh"
    command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
    remote_object="$(GH_TOKEN="${SOURCE_GH_TOKEN:-${GH_TOKEN:-}}" \
        gh api "repos/$SOURCE_GITHUB_REPOSITORY/git/ref/tags/$RELEASE_TAG")"
    remote_type="$(jq -r .object.type <<< "$remote_object")"
    remote_commit="$(jq -r .object.sha <<< "$remote_object")"
    while [[ "$remote_type" == "tag" ]]; do
        remote_object="$(GH_TOKEN="${SOURCE_GH_TOKEN:-${GH_TOKEN:-}}" \
            gh api "repos/$SOURCE_GITHUB_REPOSITORY/git/tags/$remote_commit")"
        remote_type="$(jq -r .object.type <<< "$remote_object")"
        remote_commit="$(jq -r .object.sha <<< "$remote_object")"
    done
else
    remote_refs="$(git -C "$GIT_ROOT" ls-remote origin "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}")"
    remote_commit="$(awk '$2 ~ /\^\{\}$/ { print $1; found=1 } END { if (!found && NR == 1) print $1 }' <<< "$remote_refs")"
fi
[[ -n "$remote_commit" ]] || fail "Remote release tag does not exist: $RELEASE_TAG"
[[ "$remote_commit" == "$EXPECTED_COMMIT" ]] ||
    fail "Remote release tag moved: expected $EXPECTED_COMMIT, got $remote_commit"
if [[ "$REQUIRE_HEAD_MATCH" == "1" ]]; then
    [[ "$(git -C "$GIT_ROOT" rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] ||
        fail "Release source checkout does not match approved commit: $EXPECTED_COMMIT"
fi

printf 'OK: remote release tag %s remains bound to %s.\n' "$RELEASE_TAG" "$EXPECTED_COMMIT"
