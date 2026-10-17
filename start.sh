#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn

set -euo pipefail

config_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "${value//$'\n'/ }"
    return 0
}

raise_open_file_limit() {
    # strfry aborts when relay.nofiles exceeds the container hard limit, so the
    # generated config sets nofiles = 0 and the soft limit is raised here.
    local hard_limit
    hard_limit="$(ulimit -Hn)"
    if [[ "${hard_limit}" == "unlimited" ]]; then
        hard_limit=1048576
    fi
    if ! ulimit -n "${hard_limit}"; then
        echo "==> Could not raise the open file limit; keeping $(ulimit -n)"
    fi
    return 0
}

write_config() {
    local name description contact pubkey domain
    name="$(config_value "${RELAY_NAME:-Private Nostr Relay}")"
    description="$(config_value "${RELAY_DESCRIPTION:-Private relay. Writes require an operator allowlist entry.}")"
    contact="$(config_value "${RELAY_CONTACT:-}")"
    pubkey="$(config_value "${RELAY_OPERATOR_PUBKEY:-}")"
    domain="$(config_value "${CLOUDRON_APP_DOMAIN:-}")"
    # dbParams.mapsize is left at strfry's default (10 TB of address space).
    # It is the maximum database size, not a memory reservation.
    cat > /app/data/strfry.conf <<EOF
db = "/app/data/strfry-db/"
dbParams { maxreaders = 256 }
relay {
    bind = "0.0.0.0"
    port = 7777
    nofiles = 0
    realIpHeader = "x-real-ip"
    info { name = "${name}" description = "${description}" contact = "${contact}" pubkey = "${pubkey}" }
    auth { enabled = false serviceUrl = "wss://${domain}" }
    writePolicy { plugin = "/app/code/plugins/allowlist.py" timeoutSeconds = 10 }
}
EOF
    return 0
}

main() {
    mkdir -p /app/data/strfry-db
    touch /app/data/allowlist.txt
    chown -R cloudron:cloudron /app/data
    write_config
    chown cloudron:cloudron /app/data/strfry.conf
    raise_open_file_limit
    echo "==> Starting strfry with an allowlist write policy"
    exec gosu cloudron:cloudron /app/code/strfry --config /app/data/strfry.conf relay
}

main "$@"
