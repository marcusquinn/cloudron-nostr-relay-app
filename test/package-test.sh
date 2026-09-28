#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${TEST_DIR%/*}"

fail() {
    local message="$1"
    printf 'FAIL: %s\n' "${message}" >&2
    return 1
}

main() {
    jq -e '.id == "com.marcusquinn.cloudron.strfry" and .version == "0.1.0" and .upstreamVersion == "1.1.3" and .httpPort == 7777 and .healthCheckPath == "/" and .addons.localstorage == {} and .manifestVersion == 2 and .minBoxVersion == "9.1.0"' "${ROOT_DIR}/CloudronManifest.json" >/dev/null || fail "manifest contract failed" || return 1
    grep -Fq 'cloudron/base:5.1.0@sha256:' "${ROOT_DIR}/Dockerfile" || fail "final Cloudron base is not digest pinned" || return 1
    grep -Fq 'ARG STRFRY_VERSION=1.1.3' "${ROOT_DIR}/Dockerfile" || fail "strfry version is not pinned" || return 1
    grep -Fq 'plugin = "/app/code/plugins/allowlist.py"' "${ROOT_DIR}/start.sh" || fail "write policy plugin is not configured" || return 1
    grep -Fq 'blocked: pubkey is not on the relay allowlist' "${ROOT_DIR}/plugins/allowlist.py" || fail "plugin rejection message is missing" || return 1
    bash -n "${ROOT_DIR}/start.sh"
    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "${ROOT_DIR}/plugins/allowlist.py"
    shellcheck "${ROOT_DIR}/start.sh" "${ROOT_DIR}/test/package-test.sh" "${ROOT_DIR}/test/relay-smoke.sh" "${ROOT_DIR}/scripts/publish-cloudron-catalog.sh"
    printf 'PASS: package contract\n'
    return 0
}

main "$@"
