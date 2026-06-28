# Docker Node Diff Buildkite Plugin

On a [Renovate](https://docs.renovatebot.com/) Docker-digest-update pull request, this
plugin scans the before/after images with [Syft](https://github.com/anchore/syft) and
posts the **package-level diff for every bumped image** into the PR description. When an
image's **Node.js runtime version** changed, it additionally posts the **Node.js changelog
for every release in between**. The block is refreshed in place on every build.

## Example

```yaml
steps:
  - label: ":node: changelog diff"
    plugins:
      - zbrydon/docker-node-diff#v1.0.0:
          branches:
            - renovate-docker-images
            - renovate/docker-digests
          github-token-env: GH_PR_TOKEN
```

## How it works

1. **Branch gate** - only runs on the configured `branches`, and on a pull
   request build only when the PR source repo matches the base repo (so a fork
   PR cannot drive the scan; see [Security](#security)).
2. **Diff** - `git diff <default-branch>...HEAD` (the pipeline's default branch) and
   extracts `@sha256:` image refs from the removed (`-`) and added (`+`) lines, pairing
   them by `repo:tag` then by repository. Refs are paired across the whole diff, so a
   monorepo bumping the _same_ image name in multiple files could cross-pair; this is
   correct for the typical single-image Renovate PR. Duplicate before/after pairs (e.g.
   the same image pinned via several Compose anchors) are scanned and reported once.
3. **Scan & diff packages** - `syft scan registry:<ref>` catalogues each image's packages.
   For every bumped image the report lists the package changes (added / removed / version
   bumped), including non-Node packages such as `libssl3t64`.
4. **Changelogs** - when the `node` package version moved, fetches
   `https://nodejs.org/dist/index.json`, selects every release with `before < v <= after`
   (capped at 20), and extracts each release's section from the Node.js changelog on GitHub.
5. **Upsert** - writes the report between hidden markers in the PR description via `gh`,
   replacing any previous block so the description stays current.

## Configuration

All options are optional.

| Option             | Type            | Default                  | Description                                     |
| ------------------ | --------------- | ------------------------ | ----------------------------------------------- |
| `branches`         | string \| array | `renovate-docker-images` | Branches the plugin is allowed to run on.       |
| `syft-version`     | string          | `v1.46.0`                | Pinned Syft release to download.                |
| `github-token-env` | string          | `GITHUB_TOKEN`           | Name of the env var holding the PR-write token. |

## Requirements

- `jq`, `git`, `curl`, `tar` and `gh` on the agent.
- A GitHub token with PR-write access. Without it the plugin still runs and prints the report but skips the PR update.

The `environment` hook downloads the pinned Syft release, verifies its SHA-256 against the
published `checksums.txt`, and installs it onto `PATH`. This plugin assumes **ephemeral
agents**: it re-downloads Syft each build and leaves the install dir behind, which would
accumulate on a persistent agent.

## Security

This plugin scans Docker images and renders content derived from the PR diff
into the PR description with a write-capable token. Treat the diff as the trust
boundary:

- **Fork PRs are refused.** The branch allow-list is not a trust boundary - a
  fork can name its branch anything. On a pull request build the plugin only
  runs when the PR source repo (`BUILDKITE_PULL_REQUEST_REPO`) matches the base
  repo (`BUILDKITE_REPO`). Even so, do not expose the PR-write token to
  fork/untrusted builds as a matter of pipeline policy.
- **Syft integrity.** The `environment` hook verifies the downloaded Syft
  archive against the `checksums.txt` published with the same GitHub release.
  This guards against transport corruption but not a compromised release - there
  is no cosign/GPG signature verification, so GitHub is the sole integrity root.
  Pinning `syft-version` mitigates casual tampering.

## Development

```bash
shellcheck -x hooks/environment hooks/command lib/shared.bash
bats tests/
```

## License

MIT (see [LICENSE](LICENSE)).
