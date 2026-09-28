# Packaging notes

This package builds [strfry 1.1.3](https://github.com/hoytech/strfry/tree/1.1.3)
from source. strfry is GPL-3.0; its license is included in the runtime image at
`/app/code/licenses/strfry-GPL-3.0.txt`. Repository packaging files are MIT.

The Cloudron localstorage addon persists `/app/data`, including the LMDB
database, generated configuration, and allowlist through restarts, updates,
and backups. Before an upstream strfry change that reports an incompatible DB,
use `strfry export --fried` and re-import as documented upstream.
