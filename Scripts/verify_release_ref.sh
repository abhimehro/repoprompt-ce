#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:-}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -n "$RELEASE_TAG" ]] || fail "Usage: $0 <release-tag>"
[[ "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    fail "Release tag must use canonical v<major>.<minor>.<patch> form: $RELEASE_TAG"
[[ "${GITHUB_REF:-refs/heads/main}" == "refs/heads/main" ]] ||
    fail "Release workflows must be dispatched from the protected main branch"

if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GH_TOKEN:-}" ]]; then
    command -v gh >/dev/null 2>&1 || fail "Missing required command: gh"
    command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
    remote_object="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$RELEASE_TAG")"
    remote_type="$(jq -r .object.type <<< "$remote_object")"
    tag_commit="$(jq -r .object.sha <<< "$remote_object")"
    while [[ "$remote_type" == "tag" ]]; do
        remote_object="$(gh api "repos/$GITHUB_REPOSITORY/git/tags/$tag_commit")"
        remote_type="$(jq -r .object.type <<< "$remote_object")"
        tag_commit="$(jq -r .object.sha <<< "$remote_object")"
    done
    main_commit="$(git rev-parse HEAD)"
    compare_status="$(gh api "repos/$GITHUB_REPOSITORY/compare/$tag_commit...$main_commit" --jq .status)"
    [[ "$compare_status" == "ahead" || "$compare_status" == "identical" ]] ||
        fail "Release tag $RELEASE_TAG is not reachable from protected main"
else
    git fetch --force origin main "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"
    tag_commit="$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}" 2>/dev/null || true)"
    [[ -n "$tag_commit" ]] || fail "Release tag does not exist: $RELEASE_TAG"
    git merge-base --is-ancestor "$tag_commit" refs/remotes/origin/main ||
        fail "Release tag $RELEASE_TAG is not reachable from protected main"
fi

printf '%s\n' "$tag_commit"
