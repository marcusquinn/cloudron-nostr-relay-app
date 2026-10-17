# Live qualification record

Each release is qualified on a disposable app on a real Cloudron, installed
from the public versions URL, before Community Apps submission or promotion.
The checks run with `test/live-qualification.sh`, which uses throwaway keys
only. See `docs/PUBLISHING.md` for the procedure.

## 0.1.0 — 2026-10-17

- Install: `cloudron install --versions-url https://raw.githubusercontent.com/marcusquinn/cloudron-nostr-relay-app/main/CloudronVersions.json --location relay-test.<domain>`
- Image: `ghcr.io/marcusquinn/cloudron-nostr-relay-app@sha256:da17b0d66cb659dfb54a071d11879c06cbaf814c810698afd9d64e4ab18da48e`

| Check | Result |
|-------|--------|
| Install from public versions URL; health check passes over Cloudron TLS | Pass |
| NIP-11 `name`/`contact` follow `RELAY_NAME`/`RELAY_CONTACT` (`cloudron env set`) | Pass |
| Empty allowlist rejects writes with `blocked: pubkey is not on the relay allowlist` | Pass |
| Allowlisted `npub` write over `wss://` accepted and stored, no restart needed | Pass |
| Non-allowlisted write rejected and not stored | Pass |
| Event and allowlist persist across `cloudron restart` | Pass |
| Backup, then restore: backed-up event and allowlist present, post-backup write rolled back, policy still enforced | Pass (2 runs) |
| No `NOFILES`, `MDB_MAP_FULL` or plugin `Traceback` in app logs | Pass |

Commands:

```bash
test/live-qualification.sh relay-test.<domain> full --with-backup-restore
test/live-qualification.sh relay-test.<domain> seed <state-file>
```

## Update 0.1.0 → 0.1.1

Pending: run `verify-seed` with the state file seeded on 0.1.0, after the app
updates to 0.1.1.
