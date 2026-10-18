## What

The README badge block renders the wide "Languages by lines of code" chart
inline with the lines-of-code and dependencies badges, so GitHub bottom-aligns
the small badges against a large white panel. The block is a stale render of
the pre-GH#34145 aidevops template (category comments, inline language chart,
`license: see file`, a workflow-name Actions badge and a generic GitHub link).

## Why

The README is the public landing page; the current layout looks broken.

## How

- `README.md`: regenerate the managed block with
  `~/.aidevops/agents/scripts/readme-badges-helper.sh inject README.md marcusquinn/cloudron-nostr-relay-app`
  so the chart sits in its own paragraph after the badge rows; keep a blank
  line after `<!-- aidevops:badges:end -->`.
- `docs/metrics/`: refresh with `~/.aidevops/agents/scripts/repo-metrics-helper.sh generate`
  so `languages.svg` uses the current dark-mode-aware chart.

### Files Scope

- `README.md`
- `docs/metrics/repo-metrics.json`
- `docs/metrics/repo-metrics.md`
- `docs/metrics/badges/languages.svg`
- `docs/metrics/badges/loc.svg`
- `docs/metrics/badges/dependencies.svg`

## Acceptance

- `readme-badges-helper.sh check README.md marcusquinn/cloudron-nostr-relay-app` exits 0.
- The languages chart line is separated from other badges by blank lines.
- Licence badge shows MIT.

## Verification

`readme-badges-helper.sh check README.md marcusquinn/cloudron-nostr-relay-app`
and visual inspection of the rendered README on the PR branch.
