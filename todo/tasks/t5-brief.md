# t5: Qualify strfry relay package on Cloudron and submit to Community Apps

## Origin

- **Created:** 2026-09-27
- **Session:** opencode:ses_f1f59ba62ffeapMbfcXvy05cN5
- **Created by:** ai-interactive (Marcus Quinn session)
- **Blocked by:** t4 (package implementation PR merged)
- **Conversation context:** Operator half of the private relay package lifecycle. These steps need the maintainer's GitHub secret, Cloudron server and Cloudron Community Apps account, so they are not worker-dispatchable.

## What

The relay package from t4 is published, qualified on a live Cloudron, and listed in Cloudron Community Apps.

## Why

Community Apps submission is the stated end goal and needs maintainer credentials and a real install.

## How (operator checklist)

1. Create a fine-grained PAT limited to this repository with only `Contents: Read and write`; save it as the repository secret `CLOUDRON_RELEASE_PAT` (see `docs/PUBLISHING.md`).
2. Merge the t4 PR and confirm the catalog workflow published the image, `CloudronVersions.json`, tag and GitHub release.
3. Install: `cloudron install --versions-url <PUBLIC_VERSIONS_URL> --location relay-test`.
4. Qualify: add your npub to `/app/data/allowlist.txt`; publish from a Nostr client with that key (accepted) and with another key (rejected); NIP-11 info shows the configured name/contact; restart, update and backup/restore keep events and the allowlist.
5. Sign in at [Cloudron Community Apps](https://ca.cloudron.io), add the versions URL, and verify the imported listing.
6. Record evidence in the issue.

## Acceptance Criteria

- [ ] Allowlisted writes succeed and other writes are rejected on the live install.
- [ ] Events and allowlist survive restart, update and backup/restore.
- [ ] The app appears in Cloudron Community Apps with correct metadata.

## Dependencies

- **Blocked by:** t4
- **External:** GitHub PAT, Cloudron server admin access, Cloudron Community Apps account.
