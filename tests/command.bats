#!/usr/bin/env bats

B_DIGEST="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
A_DIGEST="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/command"

  REPO="$(mktemp -d)"
  (
    cd "$REPO"
    git init -q
    git config user.email t@t.com
    git config user.name t
    git checkout -q -b main
    printf 'FROM node:20@sha256:%s\n' "$B_DIGEST" >Dockerfile
    git add -A && git commit -qm init
    git checkout -q -b renovate-docker-images
    printf 'FROM node:20@sha256:%s\n' "$A_DIGEST" >Dockerfile
    git add -A && git commit -qm bump
  )

  STUB="$(mktemp -d)"
  GH_LOG="$(mktemp)"
  PR_BODY_FILE="$(mktemp)"
  export GH_LOG PR_BODY_FILE

  # syft stub: map digest -> node version (default: 20.9.0 -> 20.11.0)
  syft_versions "20.9.0" "20.11.0"

  cat >"${STUB}/curl" <<'EOF'
#!/bin/bash
url=""; out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in http*) url="$a";; esac
  prev="$a"
done
emit() { if [ -n "$out" ]; then printf '%s' "$1" >"$out"; else printf '%s' "$1"; fi; }
case "$url" in
  *nodejs.org/dist/index.json)
    emit '[{"version":"v20.11.0"},{"version":"v20.10.0"},{"version":"v20.9.0"},{"version":"v20.8.0"}]' ;;
  *CHANGELOG_V20.md)
    emit '<a id="20.11.0"></a>
## Version 20.11.0
eleven.
<a id="20.10.0"></a>
## Version 20.10.0
ten.
<a id="20.9.0"></a>
## Version 20.9.0
nine.' ;;
  *) emit '' ;;
esac
EOF
  chmod +x "${STUB}/curl"

  cat >"${STUB}/gh" <<EOF
#!/bin/bash
echo "gh \$*" >> "${GH_LOG}"
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  cat "${PR_BODY_FILE}"
elif [ "\$1" = "pr" ] && [ "\$2" = "edit" ]; then
  bf=""; prev=""
  for a in "\$@"; do [ "\$prev" = "--body-file" ] && bf="\$a"; prev="\$a"; done
  cp "\$bf" "${PR_BODY_FILE}"
fi
EOF
  chmod +x "${STUB}/gh"
}

teardown() {
  rm -rf "${REPO}" "${STUB}" "${GH_LOG}" "${PR_BODY_FILE}"
}

# syft_versions BEFORE AFTER -> rewrite the syft stub
syft_versions() {
  cat >"${STUB}/syft" <<EOF
#!/bin/bash
ref=""
for a in "\$@"; do case "\$a" in registry:*) ref="\$a";; esac; done
case "\$ref" in
  *${B_DIGEST}*) ver="$1" ;;
  *${A_DIGEST}*) ver="$2" ;;
  *) ver="" ;;
esac
if [ -n "\$ver" ]; then
  printf '{"artifacts":[{"name":"node","type":"binary","version":"%s"}]}\n' "\$ver"
else
  printf '{"artifacts":[]}\n'
fi
EOF
  chmod +x "${STUB}/syft"
}

run_hook() {
  # $1 = BUILDKITE_PULL_REQUEST value, $2 = branch (default renovate-docker-images)
  run env -i \
    PATH="${STUB}:${PATH}" \
    HOME="${HOME}" \
    BUILDKITE_BRANCH="${2:-renovate-docker-images}" \
    BUILDKITE_PIPELINE_DEFAULT_BRANCH="main" \
    BUILDKITE_PULL_REQUEST="$1" \
    BUILDKITE_PULL_REQUEST_REPO="https://github.com/acme/widget.git" \
    GITHUB_TOKEN="tok" \
    bash -c "cd '${REPO}' && bash '${HOOK}'"
}

@test "reports a version change with the in-range releases" {
  printf 'Original body.\n' >"${PR_BODY_FILE}"
  run_hook 42
  [ "$status" -eq 0 ]
  grep -q "docker-node-diff:start" "${PR_BODY_FILE}"
  grep -q 'Node.js `20.9.0` → `20.11.0`' "${PR_BODY_FILE}"
  grep -q "v20.11.0</summary>" "${PR_BODY_FILE}"
  grep -q "v20.10.0</summary>" "${PR_BODY_FILE}"
  # the before-version is not in range (before < v <= after)
  ! grep -q "v20.9.0</summary>" "${PR_BODY_FILE}"
  grep -q "Original body." "${PR_BODY_FILE}"
}

@test "re-run replaces the block in place (idempotent)" {
  printf 'Original body.\n' >"${PR_BODY_FILE}"
  run_hook 42
  run_hook 42
  [ "$(grep -c "docker-node-diff:start" "${PR_BODY_FILE}")" -eq 1 ]
}

@test "replaces a large existing block in place (no SIGPIPE append)" {
  # Block interior > 64KB pipe buffer: the old printf|grep -q pipeline took
  # SIGPIPE (status 141) and appended a second block instead of replacing.
  {
    echo "Original body."
    echo "<!-- docker-node-diff:start -->"
    head -c 70000 </dev/zero | tr '\0' x
    echo
    echo "<!-- docker-node-diff:end -->"
  } >"${PR_BODY_FILE}"
  run_hook 42
  [ "$status" -eq 0 ]
  [ "$(grep -c "docker-node-diff:start" "${PR_BODY_FILE}")" -eq 1 ]
}

@test "no version change clears a stale block" {
  printf 'Original body.\n' >"${PR_BODY_FILE}"
  run_hook 42
  grep -q "v20.11.0</summary>" "${PR_BODY_FILE}"
  syft_versions "20.9.0" "20.9.0"
  run_hook 42
  grep -q "No Node.js runtime version changes" "${PR_BODY_FILE}"
  ! grep -q "v20.11.0</summary>" "${PR_BODY_FILE}"
}

@test "no changes and no existing block leaves the PR untouched" {
  syft_versions "20.9.0" "20.9.0"
  printf 'Pristine body.\n' >"${PR_BODY_FILE}"
  run_hook 42
  [ "$(cat "${PR_BODY_FILE}")" = "Pristine body." ]
}

@test "non-PR build skips the PR update" {
  printf 'untouched\n' >"${PR_BODY_FILE}"
  run_hook false
  [ "$status" -eq 0 ]
  [ ! -s "${GH_LOG}" ]
  [ "$(cat "${PR_BODY_FILE}")" = "untouched" ]
}

@test "branch not in allow-list is skipped" {
  run_hook false "feature/x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in allow-list"* ]]
}

@test "non-node image is skipped" {
  syft_versions "" ""
  printf 'body\n' >"${PR_BODY_FILE}"
  run_hook 42
  [ "$status" -eq 0 ]
  grep -q "No Node.js runtime version changes" "${PR_BODY_FILE}" || [ "$(cat "${PR_BODY_FILE}")" = "body" ]
}

@test "handles multiple changed images" {
  (
    cd "$REPO"
    # base (main) carries both images; branch bumps both digests
    git checkout -q main
    printf 'FROM node:20@sha256:%s\nFROM node:18@sha256:%s\n' \
      "$B_DIGEST" "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd" >Dockerfile
    git add -A && git commit -qm base-multi
    git branch -qD renovate-docker-images
    git checkout -q -b renovate-docker-images
    printf 'FROM node:20@sha256:%s\nFROM node:18@sha256:%s\n' \
      "$A_DIGEST" "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" >Dockerfile
    git add -A && git commit -qm bump-multi
  )
  # second image (node:18) maps cccc -> 18.x; extend syft stub
  cat >"${STUB}/syft" <<EOF
#!/bin/bash
ref=""
for a in "\$@"; do case "\$a" in registry:*) ref="\$a";; esac; done
case "\$ref" in
  *${B_DIGEST}*) ver="20.9.0" ;;
  *${A_DIGEST}*) ver="20.11.0" ;;
  *dddddddddddd*) ver="18.18.0" ;;
  *cccccccccccc*) ver="18.19.0" ;;
  *) ver="" ;;
esac
printf '{"artifacts":[{"name":"node","type":"binary","version":"%s"}]}\n' "\$ver"
EOF
  chmod +x "${STUB}/syft"
  printf 'body\n' >"${PR_BODY_FILE}"
  run_hook 42
  grep -q "2 Docker image(s) bumped" "${PR_BODY_FILE}"
}
