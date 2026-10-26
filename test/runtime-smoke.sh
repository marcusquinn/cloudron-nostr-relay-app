#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn
#
# Local container smoke test for a built relay image.
#
# Usage: test/runtime-smoke.sh <image>
# Requires: docker, curl, jq and nak (https://github.com/fiatjaf/nak) on PATH,
# or NAK=/path/to/nak.
# CI: test/runtime-smoke.sh --ci builds linux/amd64 and downloads the
# checksum-pinned Linux nak client to a temporary directory (no root required).
#
# The test mimics the Cloudron runtime (read-only root filesystem, writable
# /app/data, /tmp and /run, open-file hard limit 524288). It owns only one
# labelled container and one labelled volume, removed on exit. It publishes the
# relay port on 127.0.0.1 only and never contacts a remote host.

set -euo pipefail

IMAGE="${1:-}"
NAK="${NAK:-nak}"
RUN_ID="$(date +%s)-$$"
LABEL="io.marcusquinn.nostr-relay.smoke=${RUN_ID}"
CONTAINER="nostr-relay-smoke-${RUN_ID}"
VOLUME="nostr-relay-smoke-${RUN_ID}"
RELAY_URL=""
HTTP_URL=""

run_ci() (
    local scratch image script_dir
    scratch="$(mktemp -d)"
    image="nostr-relay-smoke:${RUN_ID}"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    trap 'docker image rm "${image}" >/dev/null 2>&1 || true; rm -rf -- "${scratch}"' EXIT
    # Keep the client version and checksum paired with the former inline job.
    curl --fail --silent --show-error --location \
        'https://github.com/fiatjaf/nak/releases/download/v0.21.2/nak-v0.21.2-linux-amd64' \
        --output "${scratch}/nak"
    printf '%s  %s\n' \
        '0acd56fea6ab1b9a0a68c8615670c6f8eff9e8878922442e387b94ee15266bb8' \
        "${scratch}/nak" | sha256sum -c -
    chmod 0755 "${scratch}/nak"
    docker build --platform linux/amd64 --tag "${image}" "${script_dir}/.."
    NAK="${scratch}/nak" bash "${script_dir}/runtime-smoke.sh" "${image}"
    return 0
)

cleanup() {
    local status="$?"
    if [[ "${status}" != "0" ]] && docker inspect "${CONTAINER}" >/dev/null 2>&1; then
        printf -- '--- container logs (failure) ---\n' >&2
        docker logs --tail 80 "${CONTAINER}" >&2 2>&1 || true
    fi
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
    printf 'cleanup: removed container and volume labelled %s\n' "${LABEL}"
    return "${status}"
}

fail() {
    local message="$1"
    printf 'FAIL: %s\n' "${message}" >&2
    return 1
}

wait_for_http() {
    local deadline=$((SECONDS + 90))
    local port=""
    while ((SECONDS < deadline)); do
        port="$(docker port "${CONTAINER}" 7777/tcp 2>/dev/null | awk -F: 'NR == 1 { print $NF }')"
        if [[ -n "${port}" ]] && curl -fsS -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then
            HTTP_URL="http://127.0.0.1:${port}/"
            RELAY_URL="ws://127.0.0.1:${port}"
            return 0
        fi
        if [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" != "true" ]]; then
            fail "container exited before the health check passed" || return 1
        fi
        sleep 2
    done
    fail "health check on / did not return 200 within 90 seconds" || return 1
}

start_container() {
    docker run -d --name "${CONTAINER}" --label "${LABEL}" \
        --platform linux/amd64 \
        --read-only --tmpfs /tmp --tmpfs /run \
        --ulimit nofile=1024:524288 \
        --memory 512m \
        -v "${VOLUME}:/app/data" \
        -e CLOUDRON_APP_DOMAIN=relay.example.invalid \
        -e RELAY_NAME="Smoke Relay" \
        -e RELAY_CONTACT="smoke@example.invalid" \
        -p 127.0.0.1::7777 \
        "${IMAGE}" >/dev/null
    wait_for_http || return 1
    return 0
}

# publish <secret-key> <content>; prints nak output, returns nak's exit status
publish() {
    local secret="$1"
    local content="$2"
    # nak reads an event from stdin when stdin is not a terminal (as in CI),
    # so give it an explicitly empty stdin plus --github.
    "${NAK}" event --github --sec "${secret}" -c "${content}" "${RELAY_URL}" 2>&1 </dev/null
    return $?
}

count_events() {
    local author="$1"
    "${NAK}" req -a "${author}" -k 1 "${RELAY_URL}" 2>/dev/null </dev/null | jq -s 'length'
    return 0
}

main() {
    local writer_sec writer_pub writer_npub stranger_sec stranger_pub
    local info accepted_output rejected_output
    [[ -n "${IMAGE}" ]] || fail "usage: test/runtime-smoke.sh <image>" || return 1
    command -v "${NAK}" >/dev/null || fail "nak not found; set NAK=/path/to/nak" || return 1
    trap cleanup EXIT

    writer_sec="$("${NAK}" key generate)"
    writer_pub="$("${NAK}" key public "${writer_sec}")"
    writer_npub="$("${NAK}" encode npub "${writer_pub}")"
    stranger_sec="$("${NAK}" key generate)"
    stranger_pub="$("${NAK}" key public "${stranger_sec}")"

    docker volume create --label "${LABEL}" "${VOLUME}" >/dev/null
    start_container || return 1
    printf 'ok: health check / returned 200 under a read-only root filesystem\n'

    info="$(curl -fsS -H 'Accept: application/nostr+json' "${HTTP_URL}")"
    jq -e '.name == "Smoke Relay" and .contact == "smoke@example.invalid"' <<<"${info}" >/dev/null ||
        fail "NIP-11 document did not reflect RELAY_NAME/RELAY_CONTACT: ${info}" || return 1
    printf 'ok: NIP-11 name and contact reflect app environment\n'

    if rejected_output="$(publish "${writer_sec}" "before-allowlist-${RUN_ID}")"; then
        : # nak may exit 0 on a relay rejection; the message is authoritative.
    fi
    grep -Fq 'blocked: pubkey is not on the relay allowlist' <<<"${rejected_output}" ||
        fail "empty allowlist did not reject a write: ${rejected_output}" || return 1
    printf 'ok: empty allowlist rejects writes\n'

    docker exec "${CONTAINER}" sh -c 'printf "# smoke writer\n%s\n" "$1" >> /app/data/allowlist.txt' _ "${writer_npub}"

    accepted_output="$(publish "${writer_sec}" "accepted-${RUN_ID}")" ||
        fail "allowlisted npub write failed: ${accepted_output}" || return 1
    grep -Fq 'blocked' <<<"${accepted_output}" && { fail "allowlisted npub write was blocked: ${accepted_output}" || return 1; }
    [[ "$(count_events "${writer_pub}")" == "1" ]] || fail "allowlisted event was not stored" || return 1
    printf 'ok: allowlisted npub write accepted and stored without restart\n'

    if rejected_output="$(publish "${stranger_sec}" "stranger-${RUN_ID}")"; then
        :
    fi
    grep -Fq 'blocked: pubkey is not on the relay allowlist' <<<"${rejected_output}" ||
        fail "non-allowlisted write was not rejected: ${rejected_output}" || return 1
    [[ "$(count_events "${stranger_pub}")" == "0" ]] || fail "non-allowlisted event was stored" || return 1
    printf 'ok: non-allowlisted write rejected and not stored\n'

    docker restart "${CONTAINER}" >/dev/null
    wait_for_http || return 1
    [[ "$(count_events "${writer_pub}")" == "1" ]] || fail "event did not survive restart" || return 1
    docker exec "${CONTAINER}" grep -Fqx "${writer_npub}" /app/data/allowlist.txt ||
        fail "allowlist did not survive restart" || return 1
    printf 'ok: event and allowlist persist across restart\n'

    if docker logs "${CONTAINER}" 2>&1 | grep -Eq 'NOFILES|MDB_MAP_FULL|Traceback'; then
        fail "relay logs contain startup or plugin errors" || return 1
    fi
    printf 'PASS: runtime smoke for %s\n' "${IMAGE}"
    return 0
}

if [[ "${IMAGE}" == "--ci" ]]; then
    run_ci
else
    main "$@"
fi
