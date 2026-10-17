#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn
#
# Live qualification of an installed relay app on a real Cloudron.
#
# Usage:
#   test/live-qualification.sh <app-location> full [--with-backup-restore]
#   test/live-qualification.sh <app-location> seed <state-file>
#   test/live-qualification.sh <app-location> verify-seed <state-file>
#   test/live-qualification.sh <app-location> update-from-catalog <version>
#
# Requires: cloudron CLI (logged in), curl, jq and nak on PATH (or NAK=...).
#
# Run it only against a disposable test app. All keys are freshly generated
# throwaway keys.
#
# full: sets NIP-11 env vars (restarts the app), checks rejected and accepted
#   writes, and restarts the app. --with-backup-restore also creates a backup
#   and restores the app from it, discarding writes made after that backup.
# seed: allowlists a throwaway key and stores one event, keeping both. The key
#   is saved to <state-file> (mode 600) for verify-seed after an app update.
# verify-seed: checks that the seeded event and allowlist entry survived and the
#   write policy still applies, then removes the seeded allowlist entry.
# update-from-catalog: updates the app to <version> using the manifest and image
#   digest published in the public catalog (VERSIONS_URL), then checks the
#   running digest. Plain `cloudron update` inside this repository uploads the
#   local source and builds it on the server instead, and CLI 8.2.6 cannot
#   update from a versions URL, so this mode sends the published manifest from
#   an empty scratch directory.
#
# full and verify-seed remove their marked allowlist lines on exit. Test events
# stay in the test database.

set -euo pipefail

APP="${1:-}"
MODE="${2:-}"
MODE_ARG="${3:-}"
NAK="${NAK:-nak}"
VERSIONS_URL="${VERSIONS_URL:-https://raw.githubusercontent.com/marcusquinn/cloudron-nostr-relay-app/main/CloudronVersions.json}"
RUN_ID="$(date +%s)-$$"
MARKER="# live-qualification ${RUN_ID}"
RELAY_URL="wss://${APP}"
HTTP_URL="https://${APP}/"
QUAL_NAME="Qualification Relay ${RUN_ID}"
QUAL_CONTACT="qualification@example.invalid"
WRITER_SEC=""
WRITER_PUB=""
WRITER_NPUB=""

fail() {
    local message="$1"
    printf 'FAIL: %s\n' "${message}" >&2
    return 1
}

app_exec() {
    cloudron exec --app "${APP}" -- "$@" </dev/null
    return $?
}

remove_allowlist_entry() {
    local marker="$1"
    local npub="$2"
    # shellcheck disable=SC2016 # $1/$2 are expanded by the in-app shell.
    app_exec sh -c 'grep -vF "$1" /app/data/allowlist.txt > /tmp/allowlist.new; grep -vxF "$2" /tmp/allowlist.new > /app/data/allowlist.txt || true; rm -f /tmp/allowlist.new' _ "${marker}" "${npub}" >/dev/null 2>&1 || true
    printf 'cleanup: removed qualification allowlist entry (%s)\n' "${marker}"
    return 0
}

cleanup() {
    local status="$?"
    remove_allowlist_entry "${MARKER}" "${WRITER_NPUB:-__none__}"
    return "${status}"
}

add_allowlist_entry() {
    local marker="$1"
    local npub="$2"
    # shellcheck disable=SC2016 # $1/$2 are expanded by the in-app shell.
    app_exec sh -c 'printf "%s\n%s\n" "$1" "$2" >> /app/data/allowlist.txt' _ "${marker}" "${npub}" >/dev/null
    return $?
}

new_writer() {
    WRITER_SEC="$("${NAK}" key generate)"
    WRITER_PUB="$("${NAK}" key public "${WRITER_SEC}")"
    WRITER_NPUB="$("${NAK}" encode npub "${WRITER_PUB}")"
    return 0
}

wait_for_http() {
    local deadline=$((SECONDS + 180))
    while ((SECONDS < deadline)); do
        if curl -fsS -o /dev/null "${HTTP_URL}" 2>/dev/null; then
            return 0
        fi
        sleep 3
    done
    fail "health check on ${HTTP_URL} did not return 200 within 180 seconds" || return 1
}

publish() {
    local secret="$1"
    local content="$2"
    "${NAK}" event --sec "${secret}" -c "${content}" "${RELAY_URL}" 2>&1 </dev/null
    return $?
}

count_content() {
    local author="$1"
    local content="$2"
    "${NAK}" req -a "${author}" -k 1 "${RELAY_URL}" 2>/dev/null </dev/null |
        jq -s --arg content "${content}" '[.[] | select(.content == $content)] | length'
    return 0
}

count_author() {
    local author="$1"
    "${NAK}" req -a "${author}" -k 1 "${RELAY_URL}" 2>/dev/null </dev/null | jq -s 'length'
    return 0
}

expect_rejected() {
    local secret="$1"
    local content="$2"
    local output=""
    if output="$(publish "${secret}" "${content}")"; then
        : # nak may exit 0 on a relay rejection; the message is authoritative.
    fi
    grep -Fq 'blocked: pubkey is not on the relay allowlist' <<<"${output}" ||
        fail "write was not rejected by the allowlist: ${output}" || return 1
    return 0
}

expect_accepted() {
    local secret="$1"
    local content="$2"
    local output=""
    output="$(publish "${secret}" "${content}")" || fail "write failed: ${output}" || return 1
    if grep -Fq 'blocked' <<<"${output}"; then
        fail "allowlisted write was blocked: ${output}" || return 1
    fi
    return 0
}

expect_stranger_rejected() {
    local label="$1"
    local stranger_sec stranger_pub
    stranger_sec="$("${NAK}" key generate)"
    stranger_pub="$("${NAK}" key public "${stranger_sec}")"
    expect_rejected "${stranger_sec}" "stranger-${label}-${RUN_ID}" || return 1
    [[ "$(count_author "${stranger_pub}")" == "0" ]] || fail "non-allowlisted event was stored" || return 1
    return 0
}

print_app() {
    printf 'app: %s\n' "$(cloudron status --app "${APP}" | awk '/^(Version|Docker image):/ { gsub(/\t/, ""); printf "%s ", $0 }')"
    return 0
}

check_logs() {
    if cloudron logs --app "${APP}" --lines 500 2>&1 | grep -Eq 'NOFILES|MDB_MAP_FULL|Traceback'; then
        fail "relay logs contain startup or plugin errors" || return 1
    fi
    return 0
}

backup_restore() {
    local before_backup="$1"
    local after_backup="after-backup-${RUN_ID}"
    local backup_id
    cloudron backup create --app "${APP}" >/dev/null
    backup_id="$(cloudron backup list --app "${APP}" --raw | jq -r 'sort_by(.creationTime) | last | .id')"
    [[ -n "${backup_id}" && "${backup_id}" != "null" ]] || fail "could not find the new backup" || return 1
    expect_accepted "${WRITER_SEC}" "${after_backup}" || return 1
    [[ "$(count_content "${WRITER_PUB}" "${after_backup}")" == "1" ]] || fail "post-backup event was not stored" || return 1

    cloudron restore --app "${APP}" --backup "${backup_id}" >/dev/null
    wait_for_http || return 1
    [[ "$(count_content "${WRITER_PUB}" "${before_backup}")" == "1" ]] || fail "backed-up event missing after restore" || return 1
    [[ "$(count_content "${WRITER_PUB}" "${after_backup}")" == "0" ]] || fail "restore did not roll back to the backup" || return 1
    app_exec grep -Fqx "${WRITER_NPUB}" /app/data/allowlist.txt || fail "allowlist missing after restore" || return 1
    expect_accepted "${WRITER_SEC}" "post-restore-${RUN_ID}" || return 1
    expect_stranger_rejected "post-restore" || return 1
    printf 'ok: backup/restore keeps events and allowlist; later writes rolled back; policy still enforced\n'
    return 0
}

run_full() {
    local with_restore="$1"
    local info
    local before_backup="before-backup-${RUN_ID}"
    new_writer
    trap cleanup EXIT
    print_app

    cloudron env set --app "${APP}" "RELAY_NAME=${QUAL_NAME}" "RELAY_CONTACT=${QUAL_CONTACT}" >/dev/null
    wait_for_http || return 1
    info="$(curl -fsS -H 'Accept: application/nostr+json' "${HTTP_URL}")"
    jq -e --arg name "${QUAL_NAME}" --arg contact "${QUAL_CONTACT}" '.name == $name and .contact == $contact' <<<"${info}" >/dev/null ||
        fail "NIP-11 did not reflect RELAY_NAME/RELAY_CONTACT: ${info}" || return 1
    printf 'ok: TLS health check and NIP-11 name/contact reflect app env\n'

    expect_rejected "${WRITER_SEC}" "pre-allowlist-${RUN_ID}" || return 1
    printf 'ok: key not yet on the allowlist is rejected\n'

    add_allowlist_entry "${MARKER}" "${WRITER_NPUB}" || return 1
    expect_accepted "${WRITER_SEC}" "${before_backup}" || return 1
    [[ "$(count_content "${WRITER_PUB}" "${before_backup}")" == "1" ]] || fail "allowlisted event was not stored" || return 1
    printf 'ok: allowlisted npub write accepted over wss:// without restart\n'

    expect_stranger_rejected "full" || return 1
    printf 'ok: non-allowlisted write rejected and not stored\n'

    cloudron restart --app "${APP}" >/dev/null
    wait_for_http || return 1
    [[ "$(count_content "${WRITER_PUB}" "${before_backup}")" == "1" ]] || fail "event did not survive restart" || return 1
    app_exec grep -Fqx "${WRITER_NPUB}" /app/data/allowlist.txt || fail "allowlist did not survive restart" || return 1
    printf 'ok: event and allowlist persist across restart\n'

    if [[ "${with_restore}" == "--with-backup-restore" ]]; then
        backup_restore "${before_backup}" || return 1
    fi
    check_logs || return 1
    printf 'PASS: live qualification of %s (run %s)\n' "${APP}" "${RUN_ID}"
    return 0
}

run_seed() {
    local state_file="$1"
    local content="seed-${RUN_ID}"
    [[ -n "${state_file}" ]] || fail "seed needs a state file path" || return 1
    [[ ! -e "${state_file}" ]] || fail "state file already exists: ${state_file}" || return 1
    new_writer
    print_app
    add_allowlist_entry "${MARKER}" "${WRITER_NPUB}" || return 1
    expect_accepted "${WRITER_SEC}" "${content}" || return 1
    [[ "$(count_content "${WRITER_PUB}" "${content}")" == "1" ]] || fail "seed event was not stored" || return 1
    (umask 077 && jq -n --arg sec "${WRITER_SEC}" --arg pub "${WRITER_PUB}" --arg npub "${WRITER_NPUB}" \
        --arg marker "${MARKER}" --arg content "${content}" \
        '{sec: $sec, pub: $pub, npub: $npub, marker: $marker, content: $content}' >"${state_file}")
    printf 'ok: seeded allowlist entry and event %s; state saved to %s\n' "${content}" "${state_file}"
    return 0
}

run_verify_seed() {
    local state_file="$1"
    local marker content
    [[ -s "${state_file}" ]] || fail "state file missing or empty: ${state_file}" || return 1
    WRITER_SEC="$(jq -r '.sec' "${state_file}")"
    WRITER_PUB="$(jq -r '.pub' "${state_file}")"
    WRITER_NPUB="$(jq -r '.npub' "${state_file}")"
    marker="$(jq -r '.marker' "${state_file}")"
    content="$(jq -r '.content' "${state_file}")"
    MARKER="${marker}"
    trap cleanup EXIT
    print_app
    wait_for_http || return 1
    [[ "$(count_content "${WRITER_PUB}" "${content}")" == "1" ]] || fail "seeded event ${content} did not survive" || return 1
    app_exec grep -Fqx "${WRITER_NPUB}" /app/data/allowlist.txt || fail "seeded allowlist entry did not survive" || return 1
    expect_accepted "${WRITER_SEC}" "post-verify-${RUN_ID}" || return 1
    expect_stranger_rejected "verify" || return 1
    check_logs || return 1
    printf 'PASS: seeded event %s and allowlist entry survived; write policy still enforced\n' "${content}"
    return 0
}

run_update_from_catalog() {
    local version="$1"
    local scratch image running
    [[ -n "${version}" ]] || fail "update-from-catalog needs a version" || return 1
    scratch="$(mktemp -d)"
    curl -fsS "${VERSIONS_URL}" |
        jq -e --arg version "${version}" '.versions[$version] | select(.publishState == "published") | .manifest' \
            >"${scratch}/CloudronManifest.json" ||
        { rm -rf "${scratch}"; fail "version ${version} is not published in ${VERSIONS_URL}" || return 1; }
    image="$(jq -r '.dockerImage' "${scratch}/CloudronManifest.json")"
    [[ "${image}" == *@sha256:* ]] || { rm -rf "${scratch}"; fail "catalog image is not digest-pinned: ${image}" || return 1; }
    print_app
    # A manifest with dockerImage makes the CLI send it unchanged ("from app
    # store"), with a pre-update backup, instead of building local source.
    (cd "${scratch}" && cloudron update --app "${APP}" </dev/null) || { rm -rf "${scratch}"; return 1; }
    rm -rf "${scratch}"
    wait_for_http || return 1
    running="$(cloudron status --app "${APP}" | awk '/^Docker image:/ { print $NF }')"
    [[ "${running}" == "${image}" ]] || fail "running image ${running} is not the catalog image ${image}" || return 1
    print_app
    printf 'PASS: updated %s to catalog %s (%s)\n' "${APP}" "${version}" "${image}"
    return 0
}

main() {
    [[ -n "${APP}" && -n "${MODE}" ]] ||
        fail "usage: test/live-qualification.sh <app-location> full [--with-backup-restore] | seed <state-file> | verify-seed <state-file> | update-from-catalog <version>" || return 1
    command -v "${NAK}" >/dev/null || fail "nak not found; set NAK=/path/to/nak" || return 1
    cloudron status --app "${APP}" >/dev/null || fail "app ${APP} not found on the logged-in Cloudron" || return 1
    case "${MODE}" in
        full) run_full "${MODE_ARG}" || return 1 ;;
        seed) run_seed "${MODE_ARG}" || return 1 ;;
        verify-seed) run_verify_seed "${MODE_ARG}" || return 1 ;;
        update-from-catalog) run_update_from_catalog "${MODE_ARG}" || return 1 ;;
        *) fail "unknown mode: ${MODE}" || return 1 ;;
    esac
    return 0
}

main "$@"
