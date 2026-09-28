#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn

set -euo pipefail

fail() {
    local message="$1"
    printf 'ERROR: %s\n' "${message}" >&2
    return 1
}

main() {
    local catalog_path="${1:-CloudronVersions.json}"
    local image_ref="${2:-${EXPECTED_IMAGE_REF:-}}"
    local expected_version="${3:-${EXPECTED_VERSION:-}}"

    [[ "${catalog_path}" == "CloudronVersions.json" ]] || fail "catalog path must be CloudronVersions.json" || return 1
    [[ "${image_ref}" == *@sha256:* ]] || fail "an immutable image digest is required" || return 1
    [[ -n "${expected_version}" ]] || fail "a package version is required" || return 1
    [[ "$(jq -r '.version' CloudronManifest.json)" == "${expected_version}" ]] || fail "manifest version mismatch" || return 1

    cloudron versions add --state testing --image "${image_ref}"
    cloudron versions update --version="${expected_version}" --state=published --image "${image_ref}"
    cloudron versions verify
    return 0
}

main "$@"
