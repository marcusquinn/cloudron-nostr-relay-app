# cloudron-nostr-relay-app

<!-- AI-CONTEXT-START -->

## Quick Reference

- **Validate**: `cloudron-package-helper.sh validate`
- **Build**: `cloudron-package-helper.sh build`
- **Test install**: `cloudron-package-helper.sh install relay-test`
- **Release checks**: `cloudron-package-helper.sh check-compatibility` and
  `cloudron-package-helper.sh preflight-release vX.Y.Z`

## Project Overview

Cloudron app package for a private Nostr relay based on
[strfry](https://github.com/hoytech/strfry). It serves the relay WebSocket
behind Cloudron TLS and restricts writes to an operator-managed npub allowlist,
so it does not become an open public relay.

## Architecture

Mirror the structure of `marcusquinn/cloudron-netbird-app`: `Dockerfile` pinned to
the Cloudron base image, `start.sh`, `CloudronManifest.json`, `docs/` for
operator guides, and the Cloudron release and catalog-publish workflows.
strfry is GPL-3.0; this repository's packaging files are MIT.

## Conventions

- Commits: [Conventional Commits](https://www.conventionalcommits.org/)
- Branches: `feature/`, `bugfix/`, `hotfix/`, `refactor/`, `chore/`
- Documentation: human/operator guides in `docs/`, AI-only context in `.agents/`;
  retain conventional root entrypoints and respect existing repository conventions.

## Key Files

| File | Purpose |
|------|---------|
| `.agents/AGENTS.md` | Project-specific agent instructions |
| `docs/` | Human/operator guides, linked from root entrypoints |
| `TODO.md` | Task tracking |
| `CHANGELOG.md` | Version history |

## Package Runtime

- `CloudronManifest.json` declares the Cloudron package contract.
- `start.sh` generates the persistent strfry config and always starts closed.
- `plugins/allowlist.py` is the write-policy boundary; changes must preserve
  fail-closed behaviour.

<!-- AI-CONTEXT-END -->
