# Changelog

See [CHANGELOG](CHANGELOG) for package release notes.

## Unreleased

- Use the pinned aidevops catalog publisher while retaining package checks and
  checksum-pinned nak runtime smoke coverage. No package version change.

## 0.1.4

- Set `packagerUrl` to this repository so the Community Apps Package link opens it.
  ca.cloudron.io builds the Package link (and the "By" link) from `packagerUrl`
  and ignores `packageUrl`, so the 0.1.3 change had no visible effect
  (marcusquinn/aidevops#36428). `packageUrl` and `minBoxVersion` 10.0.0 are unchanged.
- No change to the app; strfry stays at 1.1.3.

## 0.1.3

- Set `packageUrl` so the Community Apps Package button opens this repository;
  `packagerUrl` still links the maintainer (issue #24).
- Require Cloudron 10.0.0 (`minBoxVersion`). Cloudron 9 rejects `packageUrl`
  anywhere in `CloudronVersions.json`, so 9.x servers can no longer read this
  catalog. strfry stays at 1.1.3; no app change.
