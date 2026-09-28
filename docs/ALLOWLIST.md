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

Use Cloudron's File Manager or `cloudron exec` to edit the file. The policy
plugin reads a complete fresh copy before every submitted event, so changes do
not need an app restart. Invalid, missing, or partially written entries never
grant access.
