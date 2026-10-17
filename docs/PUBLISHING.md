# Publishing to Cloudron Community Apps

`CloudronVersions.json` is the public package catalog. It is written only by
the `cloudron-catalog-publish.yml` workflow; never edit it by hand. Merging a
completed package update to `main` authorizes the workflow to publish that
manifest version.

Public versions URL:
`https://raw.githubusercontent.com/marcusquinn/cloudron-nostr-relay-app/main/CloudronVersions.json`

## Release workflow

1. Update `CloudronManifest.json` (`version`, and `upstreamVersion` with the
   Dockerfile's `STRFRY_VERSION`/`STRFRY_COMMIT`) and add a matching `CHANGELOG`
   entry. `test/package-test.sh` checks that these agree.
2. Open a pull request. CI runs the package, plugin and publisher tests, builds
   the image and runs `test/runtime-smoke.sh` against it.
3. Merge to `main`. If the manifest version is not in the catalog yet, the
   workflow:
   - reruns the tests and the container smoke test;
   - builds the amd64 image and pushes it to
     `ghcr.io/marcusquinn/cloudron-nostr-relay-app`, with build provenance;
   - waits until the exact digest can be pulled anonymously;
   - runs `scripts/publish-cloudron-catalog.sh`, which adds the version in
     testing state, checks the generated entry and digest, then promotes it to
     published;
   - attests and verifies the catalog, commits only `CloudronVersions.json`,
     pushes the commit and `v<VERSION>` tag together, and creates the GitHub
     release.
4. A merge that does not change the manifest version republishes nothing. It
   re-verifies the existing image and catalog entry and fills in a missing
   GitHub release.

The first publication creates the GHCR package. If the anonymous pull check
times out, set the package visibility to public under the repository's
Packages settings and rerun the workflow.

Published entries are append-only. For a bad release, run
`cloudron versions revoke`, bump the version and publish a new entry.

## Release credential

`main` is not a protected branch, so the workflow pushes the catalog commit
and tag with its own job token. If `main` is protected later, add the
repository secret `CLOUDRON_RELEASE_PAT`: a fine-grained token limited to this
repository with only `Contents: Read and write`. The workflow uses it only for
the final catalog commit and tag push.

## Qualification before Community Apps submission

Use a disposable app on a non-production location:

```bash
cloudron install --versions-url https://raw.githubusercontent.com/marcusquinn/cloudron-nostr-relay-app/main/CloudronVersions.json --location relay-test.example.com
```

Then run `test/live-qualification.sh` (needs the logged-in `cloudron` CLI,
`curl`, `jq` and [nak](https://github.com/fiatjaf/nak)). It uses throwaway
keys and removes its allowlist entries on exit:

```bash
# NIP-11, rejected and accepted writes, restart, backup and restore
test/live-qualification.sh relay-test.example.com full --with-backup-restore

# Update path: seed on the old version, update to the published new
# version, then verify
test/live-qualification.sh relay-test.example.com seed ./update-seed.json
test/live-qualification.sh relay-test.example.com update-from-catalog 0.1.1
test/live-qualification.sh relay-test.example.com verify-seed ./update-seed.json
```

Do not run plain `cloudron update --app …` from this repository. With no
`--image`, Cloudron CLI 8.2.6 uploads the local source and builds an
unpublished `local/…` image on the server, and it has no option to update from
a versions URL. `update-from-catalog` sends the published manifest and digest
from an empty directory instead, then checks that the running image is the
catalog digest. Operators update from the dashboard, where Cloudron offers new
versions from the versions URL.

The state file holds a throwaway private key; delete it afterwards. Record the
results in `test/QUALIFICATION.md`.

Then sign in at [ca.cloudron.io](https://ca.cloudron.io), add the versions
URL, and check the imported icon, media, description and changelog.
