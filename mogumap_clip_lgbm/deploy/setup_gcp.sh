#!/usr/bin/env bash
# Explicit infrastructure setup. Existing billing/project/secret values are required.
set -euo pipefail
: "${PROJECT_ID:?Set the existing GCP project}"
: "${REGION:=asia-northeast1}"
: "${MODEL_BUCKET:?Set the existing model bucket name}"
: "${SUPABASE_KEY_SECRET:=supabase-service-role-key}"
: "${AI_KEY_SECRET:=ai-backend-api-key}"
: "${PLACES_KEY_SECRET:=places-api-key}"
: "${TRAINER_SA_NAME:=mogumap-trainer}"
: "${SCHEDULER_SA_NAME:=mogumap-scheduler}"
: "${ARTIFACT_REPOSITORY:=mogumap-ai}"
# Caller must have project/IAM setup permissions. No keys or secret values printed.
gcloud services enable run.googleapis.com cloudscheduler.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com \
  aiplatform.googleapis.com --project="$PROJECT_ID"
for account in "$TRAINER_SA_NAME" "$SCHEDULER_SA_NAME"; do
  if ! gcloud iam service-accounts describe "$account@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$account" --project="$PROJECT_ID"
  fi
done
trainer="$TRAINER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
gcloud storage buckets add-iam-policy-binding "gs://$MODEL_BUCKET" \
  --member="serviceAccount:$trainer" --role=roles/storage.objectUser --project="$PROJECT_ID"
for secret in "$SUPABASE_KEY_SECRET" "$AI_KEY_SECRET" "$PLACES_KEY_SECRET"; do
  gcloud secrets describe "$secret" --project="$PROJECT_ID" >/dev/null
  gcloud secrets add-iam-policy-binding "$secret" --project="$PROJECT_ID" \
    --member="serviceAccount:$trainer" --role=roles/secretmanager.secretAccessor >/dev/null
done
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$trainer" \
  --role=roles/aiplatform.user --condition=None >/dev/null
if ! gcloud artifacts repositories describe "$ARTIFACT_REPOSITORY" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$ARTIFACT_REPOSITORY" --repository-format=docker \
    --location="$REGION" --project="$PROJECT_ID"
fi
