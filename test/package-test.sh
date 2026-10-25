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
    local manifest="${ROOT_DIR}/CloudronManifest.json"
    local version upstream_version
    jq -e '.id == "com.marcusquinn.cloudron.strfry" and .httpPort == 7777 and .healthCheckPath == "/" and .addons == {localstorage: {}} and .manifestVersion == 2 and .minBoxVersion == "9.1.0" and .description == "file://DESCRIPTION.md" and (.iconUrl | startswith("https://")) and (.mediaLinks | length > 0)' "${manifest}" >/dev/null || fail "manifest contract failed" || return 1
    version="$(jq -r '.version' "${manifest}")"
    upstream_version="$(jq -r '.upstreamVersion' "${manifest}")"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "manifest version is not semver" || return 1
    # Mirror the Cloudron CLI parser (src/helper.js parseChangelog): an exact
    # "[X.Y.Z]" line followed by non-empty lines up to the next "[" line.
    awk -v header="[${version}]" '
        $0 == header { found = 1; next }
        found && /^\[/ { exit }
        found && NF { entries += 1 }
        END { exit !(found && entries > 0) }
    ' "${ROOT_DIR}/CHANGELOG" || fail "CHANGELOG has no Cloudron-format \"[${version}]\" entry" || return 1
    jq -e '.stable == true and (.versions | type == "object")' "${ROOT_DIR}/CloudronVersions.json" >/dev/null || fail "CloudronVersions.json is not a valid catalog" || return 1
    [[ -s "${ROOT_DIR}/DESCRIPTION.md" ]] || fail "DESCRIPTION.md is missing" || return 1
    [[ "$(grep -Ec '^FROM cloudron/base:6\.0\.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee( AS builder)?$' "${ROOT_DIR}/Dockerfile")" == "2" ]] || fail "builder and runtime must use the reviewed digest-pinned Cloudron 6.0.1 base" || return 1
    grep -Eq '^ARG STRFRY_COMMIT=[0-9a-f]{40}$' "${ROOT_DIR}/Dockerfile" || fail "strfry source commit is not pinned" || return 1
    grep -Fq "ARG STRFRY_VERSION=${upstream_version}" "${ROOT_DIR}/Dockerfile" || fail "Dockerfile strfry version does not match upstreamVersion" || return 1
    grep -Fq 'plugin = "/app/code/plugins/allowlist.py"' "${ROOT_DIR}/start.sh" || fail "write policy plugin is not configured" || return 1
    # strfry aborts when nofiles exceeds the container hard limit (524288 on Cloudron).
    grep -Fq 'nofiles = 0' "${ROOT_DIR}/start.sh" || fail "start.sh must set relay.nofiles = 0" || return 1
    # mapsize is the maximum LMDB database size, not a memory setting.
    if grep -Eq 'mapsize[[:space:]]*=' "${ROOT_DIR}/start.sh"; then
        fail "start.sh must not cap LMDB mapsize" || return 1
    fi
    grep -Fq 'blocked: pubkey is not on the relay allowlist' "${ROOT_DIR}/plugins/allowlist.py" || fail "plugin rejection message is missing" || return 1
    bash -n "${ROOT_DIR}/start.sh"
    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "${ROOT_DIR}/plugins/allowlist.py"
    shellcheck "${ROOT_DIR}/start.sh" "${ROOT_DIR}/test/"*.sh "${ROOT_DIR}/scripts/"*.sh
    printf 'PASS: package contract\n'
    return 0
}

main "$@"
