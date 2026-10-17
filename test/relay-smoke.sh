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

    # NIP-19 test vector: npub10elfcs4f... decodes to 7e7e9c42...addf4e.
    cat > "${allowlist}/allowlist.txt" <<'LIST'
# hex entry
0000000000000000000000000000000000000000000000000000000000000001
npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg  # NIP-19 vector
npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptq
NPUB10ELFCS4FR0L0R8AF98JLMGDH9C8TCXJVZ9QKW038JS35MP4DMA8QZVJPTG
npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8q
00000000000000000000000000000000000000000000000000000000000000zz
LIST
    ALLOWLIST_PATH="${allowlist}/allowlist.txt" PLUGIN_PATH="${ROOT_DIR}/plugins/allowlist.py" \
        PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import contextlib
import importlib.util
import io
import json
import os
import sys

plugin = os.environ["PLUGIN_PATH"]
spec = importlib.util.spec_from_file_location("allowlist", plugin)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

vector_hex = "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e"
assert module.decode_npub("npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg") == vector_hex
# Corrupted checksum, uppercase, truncated and wrong-prefix entries never decode.
for invalid in (
    "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptq",
    "NPUB10ELFCS4FR0L0R8AF98JLMGDH9C8TCXJVZ9QKW038JS35MP4DMA8QZVJPTG",
    "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8q",
    "nsec10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg",
    "npub1",
    "",
):
    assert module.decode_npub(invalid) is None, invalid

allowed = module.read_allowlist(os.environ["ALLOWLIST_PATH"])
assert allowed == {f"{1:064d}", vector_hex}, sorted(allowed)

accepted = module.decision({"type": "new", "event": {"id": "accepted", "pubkey": f"{1:064d}"}}, allowed)
accepted_npub = module.decision({"type": "new", "event": {"id": "npub", "pubkey": vector_hex}}, allowed)
rejected = module.decision({"type": "new", "event": {"id": "rejected", "pubkey": f"{2:064d}"}}, allowed)
empty = module.decision({"type": "new", "event": {"id": "empty", "pubkey": f"{1:064d}"}}, set())

assert accepted["action"] == "accept", json.dumps(accepted)
assert accepted_npub["action"] == "accept", json.dumps(accepted_npub)
assert rejected["action"] == "reject" and rejected["msg"].startswith("blocked:"), json.dumps(rejected)
assert empty["action"] == "reject", json.dumps(empty)

# Exercise the strfry JSONL protocol through the plugin's main loop.
requests = [
    {"type": "new", "event": {"id": "a", "pubkey": vector_hex}},
    {"type": "new", "event": {"id": "b", "pubkey": f"{2:064d}"}},
]
module.read_allowlist.__defaults__ = (os.environ["ALLOWLIST_PATH"],)
stdin = "".join(json.dumps(request) + "\n" for request in requests) + "not json\n"
output, errors = io.StringIO(), io.StringIO()
sys.stdin = io.StringIO(stdin)
with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
    module.main()
sys.stdin = sys.__stdin__
responses = [json.loads(line) for line in output.getvalue().splitlines()]
assert [response["action"] for response in responses] == ["accept", "reject", "reject"], output.getvalue()
assert responses[0]["id"] == "a" and responses[1]["id"] == "b", output.getvalue()
assert "invalid write-policy request" in errors.getvalue(), errors.getvalue()
PY
    printf 'PASS: allowlist accepts only explicitly listed hex and npub writers\n'
    return 0
}

main "$@"
