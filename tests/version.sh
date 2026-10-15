#!/bin/bash
# No actual Git writes or network requests; also exercise sourcing under nounset.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export SOURCE="$ROOT" VERSION_SCRIPT="$ROOT/rpm/scripts/version.sh"
git() {
  [[ "$1" == -c && "$3" == -C && "$4" == "$SOURCE" ]] || return 1
  shift 4
  case "$1" in
    status) printf '%s' "${MOCK_DIRTY:-}" ;;
    rev-parse)
      if [[ "${MOCK_NO_HEAD:-}" == yes ]]; then return 1; fi
      echo 0123456789abcdef ;;
    tag) printf '%s' "${MOCK_TAG:-}" ;;
    *) return 1 ;;
  esac
}
curl() {
  case "${*: -1}" in
    */rate_limit) printf '%s' "${MOCK_RATE:-0}" ;;
    */releases) printf '%s' "${MOCK_UPSTREAM:-v1.35.1+rke2r2}" ;;
    *) return 1 ;;
  esac
  [[ "${MOCK_CURL_FAIL:-}" != yes ]]
}
jq() { cat; } # Fixtures stand in for the already parsed API fields.
export -f git curl jq
cd "$WORK"

check() (
  unset TAG DRONE_TAG GITHUB_TAG GITHUB_REF_TYPE GITHUB_REF_NAME VERSION COMMIT DRONE_COMMIT GITHUB_SHA DIRTY
  unset MOCK_DIRTY MOCK_TAG MOCK_RATE MOCK_UPSTREAM MOCK_CURL_FAIL MOCK_NO_HEAD
  local scenario=$1 before=$PWD
  case "$scenario" in
    explicit) TAG=v1.34.2-alpha9+rke2r1.latest.7 ;;
    drone) DRONE_TAG=v1.34.2+rke2r1.stable.1 ;;
    github) GITHUB_TAG=v1.34.2+rke2r1.testing.2 ;;
    github-ref) GITHUB_REF_TYPE=tag; GITHUB_REF_NAME=v1.34.2+rke2r1.latest.0 ;;
    precedence) TAG=v1.34.2+rke2r1.latest.0; DRONE_TAG=invalid; GITHUB_TAG=invalid ;;
    discovered) MOCK_TAG=$'v1.34.2+rke2r1.stable.0\nv1.34.2+rke2r1.latest.0' ;;
    dirty) TAG=v1.34.2+rke2r1.latest.0; MOCK_DIRTY=' M fixture' ;;
    api) MOCK_RATE=50 ;;
    api-null) MOCK_RATE=50; MOCK_UPSTREAM=null ;;
    api-failure) MOCK_CURL_FAIL=yes ;;
    no-tag) : ;;
    drone-commit) MOCK_NO_HEAD=yes; DRONE_COMMIT=abcdef0123456789 ;;
    github-commit) MOCK_NO_HEAD=yes; GITHUB_SHA=abcdef0123456789 ;;
    invalid) TAG=v1.34.2+rke2r1.prime.0 ;;
    no-commit) MOCK_NO_HEAD=yes ;;
  esac
  if [[ "$scenario" == invalid || "$scenario" == no-commit ]]; then
    if . "$VERSION_SCRIPT"; then echo "$scenario should fail" >&2; exit 1; fi
    return
  fi
  . "$VERSION_SCRIPT"
  [[ "$PWD" == "$before" && "$RKE2_POLICYVER" == 0.12-0 ]]
  case "$scenario" in
    explicit)
      [[ "$RKE2_VERSION" == v1.34.2-alpha9+rke2r1 && "$RPM_VERSION" == 1.34.2~alpha9~rke2r1 && "$RPM_RELEASE" == 7 && "$RPM_CHANNEL" == latest ]] ;;
    drone) [[ "$RPM_CHANNEL" == stable && "$RPM_RELEASE" == 1 ]] ;;
    github) [[ "$RPM_CHANNEL" == testing && "$RPM_RELEASE" == 2 ]] ;;
    github-ref | precedence) [[ "$RPM_CHANNEL" == latest && "$RPM_RELEASE" == 0 ]] ;;
    discovered) [[ "$RPM_CHANNEL" == stable && "$RPM_RELEASE" == 0 ]] ;;
    *)
      [[ "$RPM_CHANNEL" == testing && "$RPM_RELEASE" == 0 ]]
      case "$scenario" in
        api) [[ "$RKE2_VERSION" == v1.35.1+rke2r2 && "$RPM_MAJMIN" == 1.35 ]] ;;
        dirty) [[ "$RPM_VERSION" == 1.22.6~01234567dirty~rke2r1 && "$TREE_STATE" == dirty ]] ;;
        drone-commit | github-commit) [[ "$RPM_VERSION" == 1.22.6~abcdef01~rke2r1 ]] ;;
        *) [[ "$RPM_VERSION" == 1.22.6~01234567~rke2r1 ]] ;;
      esac ;;
  esac
)
for scenario in explicit drone github github-ref precedence discovered dirty api api-null api-failure no-tag drone-commit github-commit invalid no-commit; do
  check "$scenario"
done
echo 'Version resolution: 15 offline scenarios passed; sourcing preserves cwd and supports unset CI variables.'