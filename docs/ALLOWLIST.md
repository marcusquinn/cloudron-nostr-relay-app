# Allowlist management

The relay starts closed: an empty `/app/data/allowlist.txt` rejects every
write. Reads remain public, so encrypt content that must stay private.

Add one Nostr public key per line, either 64-character hexadecimal or NIP-19
`npub` format. Blank lines and text after `#` are ignored. For example:

```text
# Alice
npub1...
# Service key
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

An `npub` must be lowercase with a valid NIP-19 checksum; copy it from your
client rather than typing it. Never put a private key (`nsec`) in this file.
It is ignored, but the file is readable by anyone with app access.

Use Cloudron's File Manager or `cloudron exec` to edit the file, for example:

```bash
cloudron exec --app relay.example.com -- sh -c 'echo "npub1..." >> /app/data/allowlist.txt'
```

The policy plugin reads a complete fresh copy before every submitted event, so
changes do not need an app restart. Invalid, missing, or partially written
entries never grant access.

Clients that are not on the list see the event rejected with
`blocked: pubkey is not on the relay allowlist`.
