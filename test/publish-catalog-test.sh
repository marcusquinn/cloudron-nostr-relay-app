#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn
#
# Contract test for scripts/publish-cloudron-catalog.sh using a stub cloudron
# CLI. Ported from marcusquinn/cloudron-netbird-app.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
ROOT_DIR="${TEST_DIR%/*}"
TMP_ROOT=""
NEW_VERSION="0.2.0"
IMAGE_BASE="registry.example/relay"

cleanup() {
    local status="$?"
    if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
        rm -rf "${TMP_ROOT}"
    fi
    return "${status}"
}

trap cleanup EXIT

fail() {
    local message="$1"
    printf 'FAIL: %s\n' "${message}" >&2
    return 1
}

make_fixture() {
    local fixture_name="$1"
    local initial_version="${2:-0.1.0}"
    local fixture_dir="${TMP_ROOT}/${fixture_name}"

    mkdir -p "${fixture_dir}/bin"
    cp "${ROOT_DIR}/scripts/publish-cloudron-catalog.sh" "${fixture_dir}/publish-cloudron-catalog.sh"
    cat >"${fixture_dir}/CloudronManifest.json" <<JSON
{"version":"${NEW_VERSION}","upstreamVersion":"1.1.3","manifestVersion":2}
JSON
    cat >"${fixture_dir}/CloudronVersions.json" <<JSON
{"stable":true,"versions":{"${initial_version}":{"manifest":{"version":"${initial_version}","dockerImage":"${IMAGE_BASE}@sha256:old"},"publishState":"published"}}}
JSON
    cat >"${fixture_dir}/bin/cloudron" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "versions" ]] || exit 2
subcommand="${2:-}"
shift 2
catalog="CloudronVersions.json"
image=""
version=""
state=""

for argument in "$@"; do
    case "$argument" in
        --image=*) image="${argument#*=}" ;;
        --image) ;;
        --version=*) version="${argument#*=}" ;;
        --state=*) state="${argument#*=}" ;;
        testing|published) state="$argument" ;;
        *)
            if [[ -z "$image" && "$argument" == *@sha256:* ]]; then
                image="$argument"
            fi
            ;;
    esac
done

case "$subcommand" in
    add)
        manifest_version="$(jq -r '.version' CloudronManifest.json)"
        generated_key="${FAKE_GENERATED_KEY:-$manifest_version}"
        generated_manifest_version="${FAKE_MANIFEST_VERSION:-$manifest_version}"
        if [[ "$generated_manifest_version" == "__missing__" ]]; then
            generated_manifest="$(jq -cn --arg image "$image" '{dockerImage:$image}')"
        else
            generated_manifest="$(jq -cn --arg version "$generated_manifest_version" --arg image "$image" '{version:$version,dockerImage:$image}')"
        fi
        jq \
            --arg key "$generated_key" \
            --arg state "${state:-testing}" \
            --argjson manifest "$generated_manifest" \
            '.versions[$key] = {manifest:$manifest,publishState:$state}' \
            "$catalog" >"${catalog}.tmp"
        if [[ -n "${FAKE_SECOND_GENERATED_KEY:-}" ]]; then
            jq \
                --arg key "$FAKE_SECOND_GENERATED_KEY" \
                --arg state "${state:-testing}" \
                --argjson manifest "$generated_manifest" \
                '.versions[$key] = {manifest:$manifest,publishState:$state}' \
                "${catalog}.tmp" >"${catalog}.second"
            mv "${catalog}.second" "${catalog}.tmp"
        fi
        mv "${catalog}.tmp" "$catalog"
        ;;
    update)
        if [[ -z "$image" ]]; then
            printf 'missing immutable image during update\n' >&2
            exit 8
        fi
        if [[ -n "${FAKE_EXPECT_UPDATE_VERSION:-}" && "$version" != "$FAKE_EXPECT_UPDATE_VERSION" ]]; then
            printf 'wrong update target: %s\n' "$version" >&2
            exit 9
        fi
        jq --arg version "$version" --arg state "$state" --arg image "$image" '.versions[$version].publishState = $state | .versions[$version].manifest.dockerImage = $image' "$catalog" >"${catalog}.tmp"
        mv "${catalog}.tmp" "$catalog"
        ;;
    verify)
        jq -e '.stable == true and (.versions | type == "object")' "$catalog" >/dev/null
        ;;
    *) exit 3 ;;
esac
STUB
    chmod +x "${fixture_dir}/bin/cloudron" "${fixture_dir}/publish-cloudron-catalog.sh"
    printf '%s\n' "${fixture_dir}"
    return 0
}

# run_publisher <fixture_dir> <output_file> <catalog> <image_ref> [VAR=value...]
run_publisher() {
    local fixture_dir="$1"
    local output_file="$2"
    local catalog="$3"
    local image_ref="$4"
    shift 4
    (
        cd "${fixture_dir}" || exit 1
        env PATH="${fixture_dir}/bin:${PATH}" "$@" \
            ./publish-cloudron-catalog.sh "${catalog}" "${image_ref}" "${NEW_VERSION}"
    ) >"${output_file}" 2>&1
    return $?
}

expect_failure() {
    local case_name="$1"
    local expected_message="$2"
    local catalog="$3"
    local image_ref="$4"
    local initial_version="$5"
    shift 5
    local fixture_dir=""
    local output_file=""

    fixture_dir="$(make_fixture "${case_name}" "${initial_version}")" || return 1
    output_file="${fixture_dir}/output.log"
    if [[ "${catalog}" != "CloudronVersions.json" ]]; then
        cp "${fixture_dir}/CloudronVersions.json" "${fixture_dir}/${catalog}"
    fi
    if run_publisher "${fixture_dir}" "${output_file}" "${catalog}" "${image_ref}" "$@"; then
        fail "${case_name}: publisher succeeded but should have failed" || return 1
    fi
    grep -Fq "${expected_message}" "${output_file}" || fail "${case_name}: missing diagnostic '${expected_message}'" || return 1
    return 0
}

assert_successful_publish() {
    local fixture_dir=""
    local image_ref="${IMAGE_BASE}@sha256:0123456789abcdef"
    fixture_dir="$(make_fixture success)" || return 1

    run_publisher "${fixture_dir}" "${fixture_dir}/output.log" CloudronVersions.json "${image_ref}" \
        FAKE_EXPECT_UPDATE_VERSION="${NEW_VERSION}" || fail "successful publish exited non-zero" || return 1

    jq -e --arg image "${image_ref}" --arg version "${NEW_VERSION}" \
        '.versions[$version].manifest.version == $version and .versions[$version].manifest.dockerImage == $image and .versions[$version].publishState == "published"' \
        "${fixture_dir}/CloudronVersions.json" >/dev/null || fail "successful publish did not create the verified published entry" || return 1
    return 0
}

main() {
    local temp_base="${AIDEVOPS_TEMP_DIR:-${TMPDIR:-/tmp}}"
    mkdir -p "${temp_base}"
    TMP_ROOT="$(mktemp -d "${temp_base%/}/cloudron-catalog-test.XXXXXX")"

    assert_successful_publish || return 1
    expect_failure wrong-key "does not match expected version ${NEW_VERSION}" \
        CloudronVersions.json "${IMAGE_BASE}@sha256:wrong" 0.1.0 FAKE_GENERATED_KEY=0.2.1 || return 1
    expect_failure missing-manifest-version "Generated manifest version <missing> does not match ${NEW_VERSION}" \
        CloudronVersions.json "${IMAGE_BASE}@sha256:missing" 0.1.0 FAKE_MANIFEST_VERSION=__missing__ || return 1
    expect_failure multiple-entries "Expected exactly one generated catalog entry" \
        CloudronVersions.json "${IMAGE_BASE}@sha256:multiple" 0.1.0 FAKE_SECOND_GENERATED_KEY=0.2.1 || return 1
    expect_failure mutable-image "Image reference must use an immutable sha256 digest" \
        CloudronVersions.json "${IMAGE_BASE}:${NEW_VERSION}" 0.1.0 || return 1
    expect_failure duplicate-version "Catalog already contains version ${NEW_VERSION}" \
        CloudronVersions.json "${IMAGE_BASE}@sha256:duplicate" "${NEW_VERSION}" || return 1
    expect_failure non-default-catalog "requires the catalog path CloudronVersions.json" \
        AlternateVersions.json "${IMAGE_BASE}@sha256:alternate" 0.1.0 || return 1

    printf 'PASS: fail-closed Cloudron catalog publisher contract\n'
    return 0
}

main "$@"
