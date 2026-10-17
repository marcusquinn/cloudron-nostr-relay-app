Your relay URL is `wss://$CLOUDRON-APP-FQDN`.

The relay **rejects every write** until you add a public key to
`/app/data/allowlist.txt`, one `npub` or hexadecimal key per line. Edit the
file with this app's **File Manager** or **Web Terminal**. Changes apply to the
next event without a restart.

Reads are public. Never put a private key (`nsec`) in the allowlist. See the
[allowlist guide](https://github.com/marcusquinn/cloudron-nostr-relay-app/blob/main/docs/ALLOWLIST.md).
