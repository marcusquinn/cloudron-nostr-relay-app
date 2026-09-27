<!-- aidevops:brief-schema=v2 -->

# t4: Package a private strfry Nostr relay as a Cloudron app through Community Apps submission

## Pre-flight (auto-populated by briefing workflow)

- [x] Memory recall: `aidevops init new repo cloudron app community directory publishing` → 0 hits — no relevant lessons
- [x] Discovery pass: 0 commits / 0 merged PRs / 0 open PRs touch target files (new repository; `gh search repos "cloudron strfry"` and `"cloudron nostr"` returned no existing package)
- [x] File refs verified: 6 refs checked in `hoytech/strfry`, `marcusquinn/cloudron-netbird-app` and `marcusquinn/aidevops`
- [x] Tier: `tier:standard` — relay choice, storage, ports and write policy are decided; the worker composes a new package from a verified pattern
- [x] Seeded draft PR decision recorded: skipped — no package code exists yet

## Origin

- **Created:** 2026-09-27
- **Session:** opencode:ses_f1f59ba62ffeapMbfcXvy05cN5
- **Created by:** ai-interactive (Marcus Quinn session)
- **Parent task:** none
- **Blocked by:** none
- **Conversation context:** While replacing third-party mesh dependencies, the maintainer asked for a self-hosted Nostr relay packaged for Cloudron like `cloudron-netbird-app`, for private Nostr use (e.g. Buzz, and nvpn if pointed at our own relays).

## What

A publishable Cloudron app package for a private strfry relay:

- Relay WebSocket at `wss://<app domain>/` behind Cloudron TLS on `httpPort` (strfry default 7777), with NIP-11 relay information populated from Cloudron env (name, description, contact, operator pubkey).
- Writes restricted to an operator-managed npub/hex allowlist at `/app/data/allowlist.txt` via a strfry write-policy plugin; every other event is rejected with a clear `blocked:` message.
- LMDB database under `/app/data/strfry-db`, config at `/app/data/strfry.conf` generated on first run; both survive restart, update, and backup/restore.
- The same managed release pipeline shape as `cloudron-netbird-app`.
- Operator docs: allowlist editing via Cloudron File Manager or `cloudron exec`, NIP-11 settings, backup, and how to point Nostr clients (and optionally nvpn) at the relay.

## Why

Nostr apps default to public relays run by third parties. A private, allowlisted relay on our own Cloudron keeps our events and metadata on infrastructure we control, consistent with the self-hosted preference. No Cloudron package exists.

## Tier

### Tier checklist (verify before assigning)

- [ ] **Exact execution contract supplied?** No — new package files composed from a pattern.
- [x] **Targets and reference pattern verified?** Yes.
- [ ] **No semantic or design decision remains?** Minor: health path and plugin mechanics must be confirmed against strfry 1.1.3.
- [x] **Bounded, reversible, low-consequence impact?** New repository.
- [x] **No stateful coordination to invent?** Single process with LMDB.
- [x] **Focused verification and rollback are explicit?** Yes.
- [x] **No dispatch-path risk override?** Not an aidevops dispatch-path file.

**Selected tier:** `tier:standard`

**Tier rationale:** Architecture decisions are fixed; the worker composes a known package shape with bounded runtime confirmations.

## PR Conventions

Leaf task: the implementation PR uses `Resolves #<this issue>`.

## How (Approach)

### Progressive Context Plan

- **Read first:** `hoytech/strfry` at tag `1.1.3`: `README.md` (build deps, config, plugins), `strfry.conf`, `docs/plugins.md` — build and write-policy plugin contract.
- **Read first:** `marcusquinn/cloudron-netbird-app` `CloudronManifest.json`, `Dockerfile`, `docs/PUBLISHING.md`, `.github/workflows/cloudron-catalog-publish.yml`, `scripts/publish-cloudron-catalog.sh` — package and pipeline shape.
- **Load only if:** `~/.aidevops/agents/tools/deployment/cloudron-app-packaging.md` — lifecycle details.
- **Why:** strfry build/plugin contract plus a proven publication pipeline.
- **Stop when:** Dockerfile build steps, plugin I/O format, and workflow adaptations are clear.

### Worker Quick-Start

```bash
# strfry publishes tags only (no GitHub releases); latest tag 1.1.3, GPL-3.0
gh api repos/hoytech/strfry/tags --jq '.[0:3][].name'
gh api 'repos/hoytech/strfry/contents/docs/plugins.md?ref=1.1.3' --jq .content | base64 -d
gh api 'repos/hoytech/strfry/contents/strfry.conf?ref=1.1.3' --jq .content | base64 -d
```

Critical facts:

- strfry must be built from source at a pinned tag (`git clone --branch 1.1.3 --recursive`), then `make setup-golpe && make`.
- Write-policy plugins read JSON lines on stdin and answer `{"id":..., "action":"accept|reject", "msg":...}` on stdout (confirm in `docs/plugins.md`).
- strfry is GPL-3.0; this repository's packaging stays MIT and the image ships strfry's licence text.

### Files to Modify

- `NEW: CloudronManifest.json` — id `com.marcusquinn.cloudron.strfry`, `httpPort` 7777, addon `localstorage`, healthCheckPath confirmed against strfry's plain-HTTP response, metadata modelled on NetBird.
- `NEW: Dockerfile` — multi-stage: build strfry at tag `1.1.3`; final stage on the digest-pinned Cloudron base image with runtime libs only.
- `NEW: start.sh` — generate `/app/data/strfry.conf` on first run (db path, bind `0.0.0.0:7777`, NIP-11 info from env, `writePolicy.plugin`), create an empty `allowlist.txt` if missing, set LMDB `mapsize` from the Cloudron memory limit, run as `cloudron`.
- `NEW: plugins/allowlist.py` (or a small shell/Node equivalent available in the base image) — accept events whose `pubkey` is in `/app/data/allowlist.txt` (npub or hex, comments allowed), reject others; re-read the file on change.
- `NEW: CHANGELOG`, `NEW: CHANGELOG.md`, `NEW: logo.png`, `NEW: media/hero.png` — artwork licence-checked or original, provenance in `DESIGN.md`.
- `NEW: docs/README.md`, `NEW: docs/PACKAGING-NOTES.md`, `NEW: docs/PUBLISHING.md`, `NEW: docs/ALLOWLIST.md`.
- `NEW: scripts/publish-cloudron-catalog.sh`, `NEW: .github/workflows/cloudron-catalog-publish.yml`, `NEW: .github/workflows/cloudron-package-release.yml`, `NEW: .github/workflows/linked-issue-check.yml`, `NEW: .github/dependabot.yml` — adapt from NetBird; caller from the aidevops template.
- `NEW: test/package-test.sh`, `NEW: test/relay-smoke.sh` — static checks, plus a runtime check that an allowlisted key's event is accepted and a non-allowlisted key's event is rejected.
- `NEW: SECURITY.md`, `NEW: CONTRIBUTING.md`, `NEW: .dockerignore`, `NEW: .editorconfig`.
- `EDIT: README.md`, `EDIT: AGENTS.md`, `EDIT: DESIGN.md`.

### Complete Write Surface

- **Callers/readers:** Nostr clients over WebSocket and NIP-11 readers over HTTP on `httpPort` 7777; Cloudron reads `CloudronManifest.json` and `CloudronVersions.json`; aidevops `cloudron-package-monitor-helper.sh` reads the manifest.
- **Writers/mutation paths:** `start.sh` writes config and allowlist skeleton; strfry writes LMDB; operators edit `allowlist.txt`; only the catalog workflow writes `CloudronVersions.json` and tags.
- **Existing verification/tests:** none here yet; NetBird `test/package-test.sh` is the static-check pattern.
- **Schemas/config:** `strfry.conf` (strfry's own format), `CloudronManifest.json`, allowlist file format documented in `docs/ALLOWLIST.md`.
- **Generated/deployed mirrors:** GHCR image `ghcr.io/marcusquinn/cloudron-nostr-relay-app` and `CloudronVersions.json` produced by `.github/workflows/cloudron-catalog-publish.yml` only; never hand-written.
- **Migrations/backfills:** strfry LMDB format changes across upstream versions need `strfry export`/`import`; document and back up before version jumps.
- **Cleanup/rollback paths:** Cloudron backup/restore of `/app/data`; append-only catalog.

### Implementation Steps

1. Read strfry `1.1.3` build and plugin docs; confirm plugin I/O and health response.
2. Write Dockerfile, manifest, `start.sh`, plugin, docs, and pipeline following the NetBird pattern.
3. Build and run locally; publish one event from an allowlisted key and one from another key (e.g. with `nak event` or a small Python `websockets` script) and record both outcomes.
4. Run the verification block; open the PR with evidence.

### Hazards and Compatibility

- **Concurrency/atomicity:** strfry handles LMDB concurrency; allowlist reload must tolerate partial writes (read whole file, ignore invalid lines).
- **Migration/rollback:** LMDB is not portable across some upstream changes; export/import documented.
- **Mixed-version/backward compatibility:** first release; future manifests stay parseable by `minBoxVersion`.
- **Idempotency/retry:** `start.sh` safe on every restart; config keys owned by Cloudron re-applied each start without clobbering operator edits to others.
- **Partial failure/recovery:** if the plugin crashes, strfry must fail closed (reject writes) rather than accept everything; verify and document.

### Verification Before Dispatch

```bash
cloudron-package-helper.sh validate
cloudron-package-helper.sh check-compatibility
bash test/package-test.sh
bash test/relay-smoke.sh
shellcheck start.sh scripts/*.sh test/*.sh
```

- **Surface mapping:** `validate`/`check-compatibility` prove manifest and pinned base; `package-test.sh` proves static invariants; `relay-smoke.sh` proves runtime, persistence, and the allowlist accept/reject behaviour; the pull-request run of `cloudron-catalog-publish.yml` proves the pipeline validates without publishing.
- **Broad verification trigger:** Not required — new standalone repository.

### Recoverability Checkpoint

- [ ] Focused functional verification passes: `bash test/relay-smoke.sh`
- [ ] WIP commit created before broad gates: `wip: strfry cloudron package runtime`
- [ ] Evidence-triggered broad verification then run: not required — new repository

### Scope Boundaries

**Hard boundaries:** do not hand-write `CloudronVersions.json`; do not commit keys or secrets; do not run an open-write relay by default.

**AI brief owner:** marcusquinn interactive session (this brief).

**Recovery:** preserve the current PR and use the structured runtime request and Pulse intake in `reference/worker-discipline.md` when local recovery is unsafe.

### Files Scope

- `CloudronManifest.json`
- `Dockerfile`
- `.dockerignore`
- `.editorconfig`
- `start.sh`
- `plugins/allowlist.py`
- `CHANGELOG`
- `CHANGELOG.md`
- `README.md`
- `AGENTS.md`
- `DESIGN.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `logo.png`
- `media/hero.png`
- `docs/README.md`
- `docs/PACKAGING-NOTES.md`
- `docs/PUBLISHING.md`
- `docs/ALLOWLIST.md`
- `scripts/publish-cloudron-catalog.sh`
- `test/package-test.sh`
- `test/relay-smoke.sh`
- `.github/workflows/cloudron-catalog-publish.yml`
- `.github/workflows/cloudron-package-release.yml`
- `.github/workflows/linked-issue-check.yml`
- `.github/dependabot.yml`
- `TODO.md`
- `todo/tasks/t4-brief.md`

## Acceptance Criteria

- [ ] An event signed by an allowlisted key is accepted and stored; it survives a container restart.

  ```yaml
  verify:
    method: bash
    run: "bash test/relay-smoke.sh"
  ```

- [ ] An event from a key not on the allowlist is rejected, and an empty allowlist rejects all writes (no open-relay default).

  ```yaml
  verify:
    method: codebase
    pattern: "reject"
    path: "plugins"
  ```

- [ ] `cloudron-package-helper.sh validate` passes and the manifest pins no floating base image tag.

  ```yaml
  verify:
    method: bash
    run: "cloudron-package-helper.sh validate && cloudron-package-helper.sh check-compatibility"
  ```

- [ ] The pull-request run of `cloudron-catalog-publish.yml` and `linked-issue-check.yml` pass.
- [ ] `docs/PUBLISHING.md` lists the operator hand-off steps: `CLOUDRON_RELEASE_PAT` secret, live install via `cloudron install --versions-url <PUBLIC_VERSIONS_URL> --location relay-test`, upgrade/restart/backup-restore checks, and Community Apps submission at ca.cloudron.io.
- [ ] Changed-file lint is clean (`shellcheck`, markdownlint where configured).

## Context & Decisions

- strfry chosen over nostr-rs-relay: more actively maintained (last push 2026-09-04 vs 2026-05-22), LMDB performance, negentropy sync for mirroring with other relays. nostr-rs-relay (MIT, built-in pubkey whitelist) is the fallback if GPL-3.0 or the plugin model blocks packaging; record that decision in `docs/PACKAGING-NOTES.md` if taken.
- Reads stay public (strfry has no read authentication by default); privacy comes from allowlisted writes and encrypted event content. Read restriction (NIP-42) is a non-goal for 0.1.0.
- Upstream monitoring: strfry publishes tags but no GitHub releases, so the aidevops daily upstream monitor (releases API only) cannot track it yet; `monitor_upstream` stays off in `repos.json` until aidevops supports tag-only upstreams.
- Operator-only steps (secret, live Cloudron qualification, Community Apps submission) are tracked in the follow-up operator task.

## Relevant Files

- `hoytech/strfry:docs/plugins.md` — write-policy plugin contract.
- `hoytech/strfry:strfry.conf` — config keys to template.
- `marcusquinn/cloudron-netbird-app:CloudronManifest.json` — manifest pattern.
- `marcusquinn/cloudron-netbird-app:docs/PUBLISHING.md` — publication flow.
- `marcusquinn/aidevops:.agents/templates/workflows/cloudron-package-release-caller.yml` — release caller.

## Dependencies

- **Blocked by:** none
- **Blocks:** operator qualification and Community Apps submission task (t5)
- **External:** Docker on the worker host; `CLOUDRON_RELEASE_PAT` from the operator for catalog publication.

## Estimate Breakdown

| Phase | Time | Notes |
|-------|------|-------|
| Research/read | 30m | strfry build/plugin docs, NetBird reference |
| Implementation | 3h | Dockerfile, plugin, config, pipeline, docs |
| Verification | 1h | relay smoke, CI |
| **Total** | **~4.5h** | |
