#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${TEST_DIR%/*}"

main() {
    local allowlist
    allowlist="$(mktemp -d)"
    trap 'rm -rf "${allowlist:-}"' EXIT

    printf '%064d\n' 1 > "${allowlist}/allowlist.txt"
    ALLOWLIST_PATH="${allowlist}/allowlist.txt" PYTHONPATH="${ROOT_DIR}" python3 - <<'PY'
import importlib.util
import json
import os

spec = importlib.util.spec_from_file_location("allowlist", "plugins/allowlist.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

allowed = module.read_allowlist(os.environ["ALLOWLIST_PATH"])
accepted = module.decision({"type": "new", "event": {"id": "accepted", "pubkey": f"{1:064d}"}}, allowed)
rejected = module.decision({"type": "new", "event": {"id": "rejected", "pubkey": f"{2:064d}"}}, allowed)
empty = module.decision({"type": "new", "event": {"id": "empty", "pubkey": f"{1:064d}"}}, set())

assert accepted["action"] == "accept", json.dumps(accepted)
assert rejected["action"] == "reject" and rejected["msg"].startswith("blocked:"), json.dumps(rejected)
assert empty["action"] == "reject", json.dumps(empty)
PY
    printf 'PASS: allowlist accepts only explicitly listed writers\n'
    return 0
}

main "$@"
