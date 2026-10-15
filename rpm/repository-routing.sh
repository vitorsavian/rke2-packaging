#!/bin/bash
# Sourced by every sign-and-upload script before any external operations.
RPM_REPOSITORY=${RPM_REPOSITORY:-all}
case "$RPM_REPOSITORY" in
  all | prime) ;;
  *)
    echo "RPM_REPOSITORY must be all or prime, got: $RPM_REPOSITORY" >&2
    return 1
    ;;
esac

upload_rpm_repositories() {
  local destination="$TARGET_S3_PATH"
  local -a signing=(--sign)
  # Sign the same binaries once, at the first selected destination. Prime is
  # a repository location, not a separate build or version/channel suffix.
  if [[ "$RPM_REPOSITORY" == all ]]; then
    rpm_tooling --bucket "$AWS_S3_BUCKET/$destination" "${signing[@]}" \
      --sign-pass "$PRIVATE_KEY_PASS_PHRASE" \
      --aws-access-key "$AWS_ACCESS_KEY_ID" --aws-secret-key "$AWS_SECRET_ACCESS_KEY" \
      $TARGET_RPM_PATH
    signing=()
  fi
  rpm_tooling --bucket "$AWS_S3_BUCKET/$destination/prime" "${signing[@]}" \
    --sign-pass "$PRIVATE_KEY_PASS_PHRASE" \
    --aws-access-key "$AWS_ACCESS_KEY_ID" --aws-secret-key "$AWS_SECRET_ACCESS_KEY" \
    $TARGET_RPM_PATH
}