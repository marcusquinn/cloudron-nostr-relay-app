#!/usr/bin/env python3
"""Fail-closed strfry write-policy plugin backed by a persistent allowlist."""

import json
import sys

ALLOWLIST_PATH = "/app/data/allowlist.txt"
BECH32_ALPHABET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def decode_npub(value):
    """Return lowercase hex for a valid NIP-19 npub, otherwise None."""
    if not value.startswith("npub1") or value.lower() != value:
        return None
    try:
        data = [BECH32_ALPHABET.index(character) for character in value[5:]]
    except ValueError:
        return None
    if len(data) != 52:
        return None
    accumulator, bits, decoded = 0, 0, []
    for item in data:
        accumulator = (accumulator << 5) | item
        bits += 5
        while bits >= 8:
            bits -= 8
            decoded.append((accumulator >> bits) & 0xFF)
    if bits >= 5 or len(decoded) != 32:
        return None
    return bytes(decoded).hex()


def read_allowlist(path=ALLOWLIST_PATH):
    """Read a complete snapshot; malformed lines never grant access."""
    allowed = set()
    try:
        with open(path, encoding="utf-8") as allowlist:
            for raw_line in allowlist:
                item = raw_line.split("#", 1)[0].strip()
                if len(item) == 64 and all(char in "0123456789abcdefABCDEF" for char in item):
                    allowed.add(item.lower())
                else:
                    npub = decode_npub(item)
                    if npub:
                        allowed.add(npub)
    except OSError as error:
        print(f"allowlist unavailable; rejecting writes: {error}", file=sys.stderr, flush=True)
    return allowed


def decision(request, allowed):
    """Build the required strfry response for one policy request."""
    event = request.get("event", {})
    event_id = event.get("id", "")
    pubkey = event.get("pubkey", "").lower()
    if request.get("type") == "new" and pubkey in allowed:
        return {"id": event_id, "action": "accept"}
    return {"id": event_id, "action": "reject", "msg": "blocked: pubkey is not on the relay allowlist"}


def main():
    """Process JSONL requests and re-read the file for every write."""
    for line in sys.stdin:
        try:
            request = json.loads(line)
            response = decision(request, read_allowlist())
        except (json.JSONDecodeError, TypeError, AttributeError) as error:
            print(f"invalid write-policy request; rejecting: {error}", file=sys.stderr, flush=True)
            response = {"id": "", "action": "reject", "msg": "blocked: invalid policy request"}
        print(json.dumps(response, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
