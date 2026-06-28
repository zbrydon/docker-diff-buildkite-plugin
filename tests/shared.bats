#!/usr/bin/env bats

setup() {
  # shellcheck source=../lib/shared.bash
  source "${BATS_TEST_DIRNAME}/../lib/shared.bash"
}

@test "image_repo strips tag and digest" {
  run image_repo "node:20@sha256:0123456789abcdef"
  [ "$output" = "node" ]
}

@test "image_repo keeps registry port" {
  run image_repo "registry.example.com:5000/team/node:20-alpine@sha256:abc"
  [ "$output" = "registry.example.com:5000/team/node" ]
}

@test "image_repo_tag strips only the digest" {
  run image_repo_tag "registry:5000/team/node:20-alpine@sha256:abc"
  [ "$output" = "registry:5000/team/node:20-alpine" ]
}

@test "short_digest returns 12 hex chars" {
  run short_digest "node:20@sha256:0123456789abcdef0000"
  [ "$output" = "0123456789ab" ]
}

@test "version_gt is numeric, not lexical" {
  run version_gt "20.10.0" "20.9.0"
  [ "$status" -eq 0 ]
  run version_gt "20.9.0" "20.10.0"
  [ "$status" -eq 1 ]
}

@test "version_gt equal versions is false" {
  run version_gt "20.9.0" "20.9.0"
  [ "$status" -eq 1 ]
}

@test "repo_slug normalizes https, ssh, .git and trailing slash" {
  run repo_slug "https://github.com/acme/widget.git"
  [ "$output" = "acme/widget" ]
  run repo_slug "git@github.com:acme/widget.git"
  [ "$output" = "acme/widget" ]
  run repo_slug "https://github.com/acme/widget/"
  [ "$output" = "acme/widget" ]
}

@test "is_node_version accepts major.minor.patch only" {
  run is_node_version "20.11.0"
  [ "$status" -eq 0 ]
}

@test "is_node_version rejects malformed strings" {
  for v in "" "20.11" "20.11.0.1" "1.2.x" "latest" ".1.2" "1.2." "1..2"; do
    run is_node_version "$v"
    [ "$status" -ne 0 ]
  done
}

@test "plugin_read falls back to default" {
  unset BUILDKITE_PLUGIN_DOCKER_NODE_DIFF_SYFT_VERSION || true
  run plugin_read SYFT_VERSION "v1.46.0"
  [ "$output" = "v1.46.0" ]
}

@test "plugin_read reads the env var" {
  export BUILDKITE_PLUGIN_DOCKER_NODE_DIFF_SYFT_VERSION="v9.9.9"
  run plugin_read SYFT_VERSION "v1.46.0"
  [ "$output" = "v9.9.9" ]
}

@test "read_list_property collects an array" {
  export BUILDKITE_PLUGIN_DOCKER_NODE_DIFF_BRANCHES_0="a"
  export BUILDKITE_PLUGIN_DOCKER_NODE_DIFF_BRANCHES_1="b"
  read_list_property BRANCHES
  [ "${result[0]}" = "a" ]
  [ "${result[1]}" = "b" ]
}

@test "read_list_property collects a scalar" {
  export BUILDKITE_PLUGIN_DOCKER_NODE_DIFF_BRANCHES="main"
  read_list_property BRANCHES
  [ "${result[0]}" = "main" ]
}

@test "read_list_property returns non-zero when unset" {
  run read_list_property NOPE
  [ "$status" -ne 0 ]
}
