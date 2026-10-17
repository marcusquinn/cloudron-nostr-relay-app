# Packaging notes

This package builds [strfry 1.1.3](https://github.com/hoytech/strfry/tree/1.1.3)
from source, pinned to the tag's commit. The builder and runtime both use the
same digest-pinned `cloudron/base:6.0.0` image, so strfry links against the
runtime's own libraries. strfry is GPL-3.0; its license is included in the
runtime image at `/app/code/licenses/strfry-GPL-3.0.txt`. Repository packaging
files are MIT.

The Cloudron localstorage addon persists `/app/data`, including the LMDB
database, generated configuration, and allowlist through restarts, updates,
and backups. Before an upstream strfry change that reports an incompatible DB,
use `strfry export --fried` and re-import as documented upstream.

## Runtime constraints

- Cloudron app containers have an open-file hard limit of 524288. strfry exits
  at startup if `relay.nofiles` is above the hard limit (its default is
  1000000), so `start.sh` sets `nofiles = 0` and raises the soft limit itself.
- `dbParams.mapsize` is the maximum LMDB database size, not a memory setting.
  It is left at strfry's default of 10 TB of address space; resident memory
  stays within the app's memory limit.
- The root filesystem is read-only. strfry and the allowlist plugin write only
  to `/app/data`.

## Tests

```bash
bash test/package-test.sh          # static package contract and ShellCheck
bash test/relay-smoke.sh           # allowlist plugin, including NIP-19 npub vectors
bash test/publish-catalog-test.sh  # fail-closed catalog publisher
docker build --platform linux/amd64 -t nostr-relay-smoke:candidate .
bash test/runtime-smoke.sh nostr-relay-smoke:candidate   # needs nak on PATH
```

`test/runtime-smoke.sh` runs the image the way Cloudron does (read-only root,
writable `/app/data`, open-file hard limit 524288). It checks the health path,
NIP-11 output, writes from allowlisted and other keys over a real WebSocket,
and persistence across a restart. It removes only its own labelled container
and volume. CI runs it on every pull request and before every publication.
