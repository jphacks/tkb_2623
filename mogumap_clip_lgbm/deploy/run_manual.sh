#!/usr/bin/env bash
# Read-only defaults. GCP test output uses GCS manual-tests/, never publishes to DB.
set -euo pipefail
: "${PROJECT_ID:?}"
: "${REGION:=asia-northeast1}"
: "${MANUAL_JOB:=mogumap-train-test}"
: "${TRAIN_USER_ID:?Set the user UUID}"
mode="${1:---dry-run}"
case "$mode" in
  --dry-run) args='train_cli.py,--source,supabase,--dry-run' ;;
  --test) args='train_cli.py,--source,supabase,--force,--gcs-test' ;;
  --publish) args='train_cli.py,--source,supabase,--force,--publish' ;;
  *) echo 'Usage: run_manual.sh [--dry-run|--test|--publish]' >&2; exit 2 ;;
esac
gcloud run jobs execute "$MANUAL_JOB" --region="$REGION" --project="$PROJECT_ID" \
  --update-env-vars="TRAIN_USER_ID=$TRAIN_USER_ID" --args="$args" --wait
