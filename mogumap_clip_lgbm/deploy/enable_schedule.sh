#!/usr/bin/env bash
set -euo pipefail
: "${PROJECT_ID:?}"
: "${REGION:=asia-northeast1}"
: "${SCHEDULER_REGION:=$REGION}"
: "${SCHEDULE_NAME:=mogumap-train-every-five-minutes}"
gcloud scheduler jobs resume "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID"
