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

memory_limit_bytes() {
    local limit=""
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        limit="$(< /sys/fs/cgroup/memory.max)"
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        limit="$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    fi
    if [[ ! "${limit}" =~ ^[0-9]+$ ]] || ((limit < 67108864)); then
        limit=536870912
    fi
    printf '%s\n' "${limit}"
    return 0
}

write_config() {
    local mapsize="$1"
    local name description contact pubkey domain
    name="$(config_value "${RELAY_NAME:-Private Nostr Relay}")"
    description="$(config_value "${RELAY_DESCRIPTION:-Private relay. Writes require an operator allowlist entry.}")"
    contact="$(config_value "${RELAY_CONTACT:-}")"
    pubkey="$(config_value "${RELAY_OPERATOR_PUBKEY:-}")"
    domain="$(config_value "${CLOUDRON_APP_DOMAIN:-}")"
    cat > /app/data/strfry.conf <<EOF
db = "/app/data/strfry-db/"
dbParams { mapsize = ${mapsize} maxreaders = 256 }
relay {
    bind = "0.0.0.0"
    port = 7777
    realIpHeader = "x-forwarded-for"
    info { name = "${name}" description = "${description}" contact = "${contact}" pubkey = "${pubkey}" }
    auth { enabled = false serviceUrl = "wss://${domain}" }
    writePolicy { plugin = "/app/code/plugins/allowlist.py" timeoutSeconds = 10 }
}
EOF
    return 0
}

main() {
    local memory_limit mapsize
    mkdir -p /app/data/strfry-db
    touch /app/data/allowlist.txt
    chown -R cloudron:cloudron /app/data
    memory_limit="$(memory_limit_bytes)"
    mapsize=$((memory_limit / 2))
    write_config "${mapsize}"
    chown cloudron:cloudron /app/data/strfry.conf
    echo "==> Starting strfry with an allowlist write policy"
    exec gosu cloudron:cloudron /app/code/strfry --config /app/data/strfry.conf relay
}

main "$@"
