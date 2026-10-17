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

## 0.1.1 and update from 0.1.0 — 2026-10-17

- Image: `ghcr.io/marcusquinn/cloudron-nostr-relay-app@sha256:e1ecfe0d31151203bd84013999e49b479643e8255b59c7c7949195716e212d13`
- Update applied with the published catalog manifest and digest
  (`update-from-catalog`), including Cloudron's automatic pre-update backup.

| Check | Result |
|-------|--------|
| Event and allowlist entry seeded on 0.1.0 present after the update to 0.1.1 | Pass |
| After update: seeded key still writes, non-allowlisted write rejected and not stored | Pass |
| Running image equals the catalog 0.1.1 digest | Pass |
| Restore of the 0.1.0 pre-update backup returns the app to 0.1.0 with the catalog image | Pass |
| Full suite on 0.1.1 (NIP-11, writes, restart, backup/restore, logs) | Pass |
| `update-from-catalog` refuses an unpublished version | Pass |

Commands:

```bash
test/live-qualification.sh relay-test.<domain> update-from-catalog 0.1.1
test/live-qualification.sh relay-test.<domain> verify-seed <state-file>
test/live-qualification.sh relay-test.<domain> full --with-backup-restore
```

Note: a first update attempt used plain `cloudron update` from the
repository. It built the local source on the server (`local/…` image) rather
than the catalog image. That result was discarded, and the app was restored to
the 0.1.0 pre-update backup before the update above. `docs/PUBLISHING.md`
warns against this path.

Not covered: the dashboard "update available" prompt and Cloudron automatic
updates from the versions URL. Both are Cloudron server behaviour.
