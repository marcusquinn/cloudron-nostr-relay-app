# Changelog

See [CHANGELOG](CHANGELOG) for package release notes.

## Unreleased

- Use the pinned aidevops catalog publisher while retaining package checks and
  checksum-pinned nak runtime smoke coverage. No package version change.

## 0.1.3

- Set `packageUrl` so the Community Apps Package button opens this repository;
  `packagerUrl` still links the maintainer (issue #24).
- Require Cloudron 10.0.0 (`minBoxVersion`). Cloudron 9 rejects `packageUrl`
  anywhere in `CloudronVersions.json`, so 9.x servers can no longer read this
  catalog. strfry stays at 1.1.3; no app change.
