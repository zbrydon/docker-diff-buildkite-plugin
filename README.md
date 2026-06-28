# Docker Node Diff Buildkite Plugin

On a [Renovate](https://docs.renovatebot.com/) Docker-digest-update pull request, this
plugin reads the **Node.js runtime version** baked into the before/after images via
[Syft](https://github.com/anchore/syft) SBOMs, and when it changed posts the **Node.js
changelog for every release in between** into the PR description, refreshed in place on
every build.

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

1. **Branch gate** - only runs on the configured `branches`.
2. **Diff** - `git diff <default-branch>...HEAD` (the pipeline's default branch) and
   extracts `@sha256:` image refs from the removed (`-`) and added (`+`) lines, pairing
   them by `repo:tag` then by repository. Refs are paired across the whole diff, so a
   monorepo bumping the _same_ image name in multiple files could cross-pair; this is
   correct for the typical single-image Renovate PR.
3. **Read versions** - `syft scan registry:<ref>` reads the `node` artifact version from
   each image. Images without Node, or with an unchanged version, are skipped.
4. **Changelogs** - fetches `https://nodejs.org/dist/index.json`, selects every release
   with `before < v <= after` (capped at 20), and extracts each release's section from the
   Node.js changelog on GitHub.
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

## Development

```bash
shellcheck -x hooks/environment hooks/command lib/shared.bash
bats tests/
```

## License

MIT (see [LICENSE](LICENSE)).
