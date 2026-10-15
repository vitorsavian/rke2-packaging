#!/bin/bash
# Exercise real shared builders and specs with only external build tools mocked.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/source"
cp -a "$ROOT/rpm" "$WORK/source/"
export SOURCE="$WORK/source" CALLS="$WORK/calls"
export TAG=v1.34.2+rke2r1.latest.0
unset VERSION DRONE_TAG GITHUB_TAG

git() {
  if [[ "$1" == -c ]]; then
    [[ "$3" == -C && "$4" == "$SOURCE" ]] || return 1
    shift 4
  elif [[ "$1" == -C ]]; then
    [[ "$2" == "$SOURCE" ]] || return 1
    shift 2
  else return 1
  fi
  case "$1" in
    status) : ;;
    rev-parse) echo 0123456789abcdef ;;
    tag) echo "$TAG" ;;
    log) echo '- Offline changelog fixture' ;;
    *) return 1 ;;
  esac
}
mock_spectool() {
  local tool=$1
  shift
  [[ "$tool" == "$EXPECTED_TOOL" && "$1" == -gf && -f "$2" ]]
  grep -Fq "%global ARCH $EXPECTED_GOARCH" "$2"
  printf '%s\n' "$tool" >> "$CALLS"
}
spectool() { mock_spectool spectool "$@"; }
rpmdev-spectool() { mock_spectool rpmdev-spectool "$@"; }
rpmbuild() {
  local dist= topdir= arch= spec= def
  while (( $# )); do
    case "$1" in
      --define)
        def=$2
        case "$def" in
          'dist '*) dist=${def#dist } ;;
          '_topdir '*) topdir=${def#_topdir } ;;
          'rpm_version '*) [[ "$def" == 'rpm_version 1.34.2~rke2r1' ]] ;;
          'rpm_release '*) [[ "$def" == 'rpm_release 0' ]] ;;
          'rke2_policyver '*) [[ "$def" == 'rke2_policyver 0.12-0' ]] ;;
        esac
        shift 2 ;;
      --target) arch=$2; shift 2 ;;
      -ba) spec=$2; shift 2 ;;
      -vv) shift ;;
      *) echo "Unexpected rpmbuild argument: $1" >&2; return 1 ;;
    esac
  done
  [[ "$dist" == "$EXPECTED_DIST" && "$topdir" == "$RPM_TOPDIR" && "$arch" == "$EXPECTED_ARCH" ]]
  [[ -s "$(dirname "$spec")/CHANGELOG.md" ]]
  grep -q 'Offline changelog fixture' "$(dirname "$spec")/CHANGELOG.md"
  mkdir -p "$topdir/RPMS/$arch" "$topdir/SRPMS"
  spec=$(basename "$spec" .spec)
  touch "$topdir/RPMS/$arch/$spec.test.rpm" "$topdir/SRPMS/$spec.test.src.rpm"
  printf '%s\n' "$RPM_OS/$spec/$arch/$dist" >> "$CALLS"
}
curl() { echo 'Unexpected network lookup' >&2; return 1; }
chown() { printf 'chown %s\n' "$*" >> "$CALLS"; }
export -f git mock_spectool spectool rpmdev-spectool rpmbuild curl chown

# Start outside SOURCE to test path handling and source-safe version resolution.
cd "$WORK"
count=0
for RPM_OS in centos8 centos9 centos10 microos slemicro sle; do
  export RPM_OS
  case "$RPM_OS" in
    centos*) export EXPECTED_DIST= EXPECTED_TOOL=spectool ;;
    slemicro) export EXPECTED_DIST=.slemicro EXPECTED_TOOL=rpmdev-spectool ;;
    *) export EXPECTED_DIST=.sle EXPECTED_TOOL=rpmdev-spectool ;;
  esac
  grep -Fq "RPM_OS=$RPM_OS" "$ROOT/Dockerfile.$RPM_OS"
  grep -Fq 'rpm/scripts/entry.sh' "$ROOT/Dockerfile.$RPM_OS"
  for COMBARCH in x86_64-amd64 aarch64-arm64; do
    export COMBARCH EXPECTED_ARCH=${COMBARCH%-*} EXPECTED_GOARCH=${COMBARCH#*-}
    export RPM_TOPDIR="$WORK/topdir/$RPM_OS/$EXPECTED_ARCH"
    : > "$CALLS"
    bash "$SOURCE/rpm/scripts/entry.sh" build
    [[ $(wc -l < "$CALLS") == 6 ]]
    for component in common server agent; do
      grep -Fxq "$RPM_OS/rke2-$component/$EXPECTED_ARCH/$EXPECTED_DIST" "$CALLS"
      [[ -f "$SOURCE/dist/$RPM_OS/$EXPECTED_ARCH/rke2-$component.test.rpm" ]]
      [[ -f "$SOURCE/dist/$RPM_OS/source/rke2-$component.test.src.rpm" ]]
      [[ -s "$SOURCE/dist/$RPM_OS/CHANGELOG_${component^^}.md" ]]
      bash "$SOURCE/rpm/scripts/entry.sh" "build-$component"
      count=$((count + 2))
    done
  done
  actual=$(bash "$SOURCE/rpm/scripts/entry.sh" printf '%s' fallback)
  [[ "$actual" == fallback ]]
done
# Legacy CentOS 9 Dapper ownership remains optional and safely defaulted.
export RPM_OS=centos9 DAPPER_UID=1000 DAPPER_GID=1001
export EXPECTED_DIST= EXPECTED_TOOL=spectool
bash "$SOURCE/rpm/scripts/entry.sh" build-common
grep -Fxq "chown -R 1000:1001 $SOURCE" "$CALLS"
unset DAPPER_UID DAPPER_GID

for os in '' invalid '../sle'; do
  if RPM_OS=$os bash "$SOURCE/rpm/scripts/entry.sh" build > "$WORK/log" 2>&1; then exit 1; fi
  grep -q 'RPM_OS must be' "$WORK/log"
done
if COMBARCH=invalid bash "$SOURCE/rpm/scripts/build.sh" > "$WORK/log" 2>&1; then exit 1; fi
grep -q 'Combined architecture must be' "$WORK/log"
# Source specs were not modified by the shared builder.
diff -r "$ROOT/rpm/centos8" "$SOURCE/rpm/centos8"
echo "Shared builds: $count component cases passed across six OSes/two architectures; entry fallback and Dapper passed."