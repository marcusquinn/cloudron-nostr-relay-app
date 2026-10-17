#!/usr/bin/env python3
"""Fail-closed strfry write-policy plugin backed by a persistent allowlist."""

import json
import sys

ALLOWLIST_PATH = "/app/data/allowlist.txt"
BECH32_ALPHABET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32_GENERATORS = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
NPUB_HRP = "npub"
# 32-byte key = 52 five-bit groups, plus the 6-character bech32 checksum.
NPUB_DATA_LENGTH = 52
NPUB_CHECKSUM_LENGTH = 6


def bech32_polymod(values):
    """Return the BIP-173 checksum polynomial remainder for five-bit values."""
    checksum = 1
    for value in values:
        top = checksum >> 25
        checksum = ((checksum & 0x1FFFFFF) << 5) ^ value
        for index, generator in enumerate(BECH32_GENERATORS):
            if (top >> index) & 1:
                checksum ^= generator
    return checksum


def bech32_hrp_expand(hrp):
    """Expand a human-readable part for checksum computation."""
    return [ord(character) >> 5 for character in hrp] + [0] + [ord(character) & 31 for character in hrp]


def decode_npub(value):
    """Return lowercase hex for a checksum-valid NIP-19 npub, otherwise None."""
    if value.lower() != value or not value.startswith(NPUB_HRP + "1"):
        return None
    try:
        data = [BECH32_ALPHABET.index(character) for character in value[len(NPUB_HRP) + 1:]]
    except ValueError:
        return None
    if len(data) != NPUB_DATA_LENGTH + NPUB_CHECKSUM_LENGTH:
        return None
    # NIP-19 uses bech32 (constant 1), not bech32m.
    if bech32_polymod(bech32_hrp_expand(NPUB_HRP) + data) != 1:
        return None
    accumulator, bits, decoded = 0, 0, []
    for item in data[:NPUB_DATA_LENGTH]:
        accumulator = (accumulator << 5) | item
        bits += 5
        while bits >= 8:
            bits -= 8
            decoded.append((accumulator >> bits) & 0xFF)
    # Canonical encoding: leftover padding bits must be fewer than 5 and zero.
    if bits >= 5 or accumulator & ((1 << bits) - 1) or len(decoded) != 32:
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
