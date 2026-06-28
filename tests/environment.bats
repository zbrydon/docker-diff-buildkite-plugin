#!/usr/bin/env bats

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/environment"
  STUB="$(mktemp -d)"
  export PATH="${STUB}:${PATH}"

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/; s/arm64/arm64/')"
  export ASSET="syft_1.46.0_${os}_${arch}.tar.gz"

  # sha256 of the fixed fake tarball, portable across linux/macos
  if command -v sha256sum >/dev/null 2>&1; then
    GOOD_SUM="$(printf 'FAKE_SYFT_TARBALL' | sha256sum | awk '{print $1}')"
  else
    GOOD_SUM="$(printf 'FAKE_SYFT_TARBALL' | shasum -a 256 | awk '{print $1}')"
  fi
  export GOOD_SUM

  # `tar` stub: drop a fake executable syft into the -C directory.
  cat >"${STUB}/tar" <<'EOF'
#!/bin/bash
prev=""; cdir="."
for a in "$@"; do [ "$prev" = "-C" ] && cdir="$a"; prev="$a"; done
printf '#!/bin/bash\necho "syft 1.46.0"\n' > "$cdir/syft"
chmod +x "$cdir/syft"
EOF
  chmod +x "${STUB}/tar"
}

teardown() {
  rm -rf "${STUB}"
}

write_curl() {
  # $1 = checksum value to publish for the asset
  cat >"${STUB}/curl" <<EOF
#!/bin/bash
url=""; out=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  case "\$a" in http*) url="\$a";; esac
  prev="\$a"
done
case "\$url" in
  *.tar.gz)       printf 'FAKE_SYFT_TARBALL' > "\$out" ;;
  *checksums.txt) printf '%s  %s\n' "$1" "${ASSET}" > "\$out" ;;
esac
EOF
  chmod +x "${STUB}/curl"
}

@test "downloads, verifies and installs syft onto PATH" {
  write_curl "$GOOD_SUM"

  run bash -c "source '${HOOK}'; command -v syft && syft --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"syft 1.46.0"* ]]
}

@test "fails closed on checksum mismatch" {
  write_curl "deadbeefdeadbeef"

  run bash -c "source '${HOOK}'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
}

@test "downloads on every build (no cache reuse)" {
  # count invocations by appending to a marker file
  cat >"${STUB}/curl" <<EOF
#!/bin/bash
echo x >> "${STUB}/calls"
url=""; out=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  case "\$a" in http*) url="\$a";; esac
  prev="\$a"
done
case "\$url" in
  *.tar.gz)       printf 'FAKE_SYFT_TARBALL' > "\$out" ;;
  *checksums.txt) printf '%s  %s\n' "${GOOD_SUM}" "${ASSET}" > "\$out" ;;
esac
EOF
  chmod +x "${STUB}/curl"

  bash -c "source '${HOOK}'"
  bash -c "source '${HOOK}'"
  # two builds -> 4 curl calls (asset + checksums each)
  [ "$(wc -l <"${STUB}/calls")" -eq 4 ]
}
