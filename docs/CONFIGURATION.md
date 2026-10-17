# Relay configuration

The app writes `/app/data/strfry.conf` on every start, so edits to that file
are overwritten. Set the published NIP-11 relay information with app
environment variables instead:

| Variable | NIP-11 field | Default |
|----------|--------------|---------|
| `RELAY_NAME` | `name` | `Private Nostr Relay` |
| `RELAY_DESCRIPTION` | `description` | `Private relay. Writes require an operator allowlist entry.` |
| `RELAY_CONTACT` | `contact` | empty |
| `RELAY_OPERATOR_PUBKEY` | `pubkey` (`npub` or hexadecimal) | empty |

```bash
cloudron env set --app relay.example.com RELAY_NAME="Family relay" RELAY_CONTACT="admin@example.com"
```

Setting a variable restarts the app. Check the result with:

```bash
curl -H 'Accept: application/nostr+json' https://relay.example.com/
```

## Fixed settings

- Clients connect to `wss://<app-domain>/`. Cloudron terminates TLS.
- Client IP addresses come from the `X-Real-IP` header set by Cloudron's proxy.
- The database lives in `/app/data/strfry-db` and has no fixed size cap; it
  grows with stored events, within the server's disk space.
- NIP-42 authentication is off. Reads are public; writes are limited by the
  [allowlist](ALLOWLIST.md).
