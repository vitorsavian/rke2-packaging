#!/bin/bash
# Exercise the real upload entrypoints with all external commands mocked.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
cd "$WORK"

# No package installation, network access, signing, or global git config.
noop() { :; }
dnf() { noop; }
pip() { noop; }
wget() { noop; }
sha256sum() { noop; }
chmod() { noop; }
mv() { noop; }
gpg() { noop; }
git() {
  [[ "$1" == -c && "$3" == -C && "$4" == "$SOURCE" ]] || return 1
  shift 4
  case "$1" in
    rev-parse) echo 0123456789abcdef ;;
    status | config) : ;;
    *) echo "Unexpected git invocation: $*" >&2; return 1 ;;
  esac
}
rpm_tooling() {
  local bucket= sign=no pass= file=
  while (( $# )); do
    case "$1" in
      --bucket) bucket=$2; shift 2 ;;
      --sign) sign=yes; shift ;;
      --sign-pass) pass=$2; shift 2 ;;
      --aws-access-key | --aws-secret-key) shift 2 ;;
      *)
        [[ -f "$1" ]] || { echo "Missing RPM: $1" >&2; return 1; }
        file=$1; shift ;;
    esac
  done
  printf '%s|%s|%s|%s\n' "$bucket" "$sign" "$pass" "$file" >> "$CALLS"
}
export -f noop dnf pip wget sha256sum chmod mv gpg git rpm_tooling
export PRIVATE_KEY='BEGIN PGP PRIVATE KEY BLOCK'
export TESTING_PRIVATE_KEY='BEGIN PGP PRIVATE KEY BLOCK'
export PRIVATE_KEY_PASS_PHRASE='production pass phrase'
export TESTING_PRIVATE_KEY_PASS_PHRASE='testing pass phrase'
export AWS_S3_BUCKET=basic-bucket AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
export TESTING_AWS_S3_BUCKET=testing-bucket TESTING_AWS_ACCESS_KEY_ID=test TESTING_AWS_SECRET_ACCESS_KEY=test
export SOURCE="$ROOT" CALLS="$WORK/calls"
unset VERSION RPM_OS

count=0
for os in centos8 centos9 centos10 microos slemicro sle; do
  case "$os" in
    centos*) repo="centos/${os#centos}" ;;
    *) repo=$os ;;
  esac
  for arch in amd64 arm64 srcrpm; do
    export UPLOAD_ARCH=$arch
    case "$arch" in
      amd64) export COMBARCH=x86_64-amd64; rpmarch=x86_64; suffix=rpm ;;
      arm64) export COMBARCH=aarch64-arm64; rpmarch=aarch64; suffix=rpm ;;
      srcrpm) export COMBARCH=x86_64-amd64; rpmarch=source; suffix=src.rpm ;;
    esac
    file="dist/$os/$rpmarch/rke2-common.test.$suffix"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    for channel in latest stable testing; do
      export TAG="v1.34.2+rke2r1.$channel.0"
      bucket=basic-bucket
      pass=$PRIVATE_KEY_PASS_PHRASE
      if [[ "$channel" == testing ]]; then
        bucket=testing-bucket
        pass=$TESTING_PRIVATE_KEY_PASS_PHRASE
      fi
      for mode in default all prime; do
        unset RPM_REPOSITORY
        if [[ "$mode" != default ]]; then export RPM_REPOSITORY=$mode; fi
        : > "$CALLS"
        if ! RPM_OS=$os bash "$ROOT/rpm/scripts/sign-and-upload.sh" > "$WORK/log" 2>&1; then
          cat "$WORK/log" >&2
          exit 1
        fi
        path="$bucket/rke2/$channel/1.34/$repo/$rpmarch"
        if [[ "$mode" == prime ]]; then
          expected="$path/prime|yes|$pass|$file"
        else
          expected=$(printf '%s\n%s' "$path|yes|$pass|$file" "$path/prime|no|$pass|$file")
        fi
        actual=$(cat "$CALLS")
        if [[ "$actual" != "$expected" ]]; then
          printf 'Routing mismatch: %s/%s/%s/%s\nExpected:\n%s\nActual:\n%s\n' \
            "$os" "$arch" "$channel" "$mode" "$expected" "$actual" >&2
          exit 1
        fi
        count=$((count + 1))
      done
    done
  done
  # Invalid modes must fail before installing packages or uploading.
  export RPM_REPOSITORY=invalid
  : > "$CALLS"
  if RPM_OS=$os bash "$ROOT/rpm/scripts/sign-and-upload.sh" > "$WORK/log" 2>&1; then
    echo "$os accepted an invalid repository mode" >&2
    exit 1
  fi
  grep -q 'RPM_REPOSITORY must be all or prime' "$WORK/log"
  [[ ! -s "$CALLS" ]]
done
# Invalid/missing OS and architecture must fail before any external operations.
dnf() { echo 'Unexpected package installation' >> "$CALLS"; return 1; }
export -f dnf
for os in '' invalid '../sle'; do
  : > "$CALLS"
  if RPM_OS=$os bash "$ROOT/rpm/scripts/sign-and-upload.sh" > "$WORK/log" 2>&1; then
    echo 'Invalid RPM_OS accepted' >&2; exit 1
  fi
  grep -q 'RPM_OS must be' "$WORK/log"
  [[ ! -s "$CALLS" ]]
done
export RPM_REPOSITORY=all RPM_OS=sle COMBARCH=invalid
if bash "$ROOT/rpm/scripts/sign-and-upload.sh" > "$WORK/log" 2>&1; then exit 1; fi
grep -q 'Combined architecture must be' "$WORK/log"
[[ ! -s "$CALLS" ]]
echo "Repository routing: $count cases passed; all OSes reject invalid modes; invalid OS/architecture rejected."