#!/usr/bin/env bash
# Apply SQL first. Scheduler starts PAUSED; resume only after the smoke test.
set -euo pipefail
: "${PROJECT_ID:?Set the existing project}"
: "${MODEL_BUCKET:?Set the model bucket}"
: "${SUPABASE_URL:?Set the Supabase project URL}"
: "${API_SERVICE:?Set the existing Cloud Run service name}"
: "${REGION:=asia-northeast1}"
: "${SCHEDULER_REGION:=$REGION}"
: "${ARTIFACT_REPOSITORY:=mogumap-ai}"
: "${IMAGE_TAG:?Use a unique commit or release tag}"
: "${TRAINER_SA_NAME:=mogumap-trainer}"
: "${SCHEDULER_SA_NAME:=mogumap-scheduler}"
: "${TRAIN_JOB:=mogumap-train}"
: "${MANUAL_JOB:=mogumap-train-test}"
: "${SCHEDULE_NAME:=mogumap-train-every-five-minutes}"
: "${SUPABASE_KEY_SECRET:=supabase-service-role-key}"
: "${AI_KEY_SECRET:=ai-backend-api-key}"
: "${PLACES_KEY_SECRET:=places-api-key}"
: "${GEMINI_MODEL:=gemini-3.8-flash}"
: "${VERTEX_LOCATION:=global}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image="$REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPOSITORY/backend:$IMAGE_TAG"
trainer="$TRAINER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
scheduler="$SCHEDULER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
job_env="MODEL_BUCKET=$MODEL_BUCKET,SUPABASE_URL=$SUPABASE_URL,GOOGLE_CLOUD_PROJECT=$PROJECT_ID,OMP_NUM_THREADS=2"
key_secret="SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_KEY_SECRET:latest"
# CLIP is downloaded at build time and reused by Service and Jobs.
gcloud builds submit "$script_dir/.." --tag="$image" --project="$PROJECT_ID"
gcloud run jobs deploy "$TRAIN_JOB" --image="$image" --region="$REGION" --project="$PROJECT_ID" \
  --service-account="$trainer" --command=python --args=training_worker.py,--max-users,10,--max-seconds,600 \
  --tasks=1 --parallelism=1 --cpu=2 --memory=4Gi --task-timeout=1800s --max-retries=0 \
  --set-env-vars="$job_env" --set-secrets="$key_secret"
# Default execution is a read-only dry-run. --force test is explicitly invoked in run_manual.sh.
gcloud run jobs deploy "$MANUAL_JOB" --image="$image" --region="$REGION" --project="$PROJECT_ID" \
  --service-account="$trainer" --command=python --args=train_cli.py,--source,supabase,--dry-run \
  --tasks=1 --parallelism=1 --cpu=2 --memory=4Gi --task-timeout=1800s --max-retries=0 \
  --set-env-vars="$job_env" --set-secrets="$key_secret"
gcloud run jobs add-iam-policy-binding "$TRAIN_JOB" --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:$scheduler" --role=roles/run.invoker >/dev/null
# Retain the existing service's ingress/IAM policy. The shared API key remains required.
gcloud run services update "$API_SERVICE" --image="$image" --region="$REGION" --project="$PROJECT_ID" \
  --service-account="$trainer" --cpu=2 --memory=4Gi --timeout=180s --concurrency=2 \
  --update-env-vars="$job_env,GEMINI_MODEL=$GEMINI_MODEL,VERTEX_LOCATION=$VERTEX_LOCATION" \
  --update-secrets="$key_secret,AI_BACKEND_API_KEY=$AI_KEY_SECRET:latest,PLACES_API_KEY=$PLACES_KEY_SECRET:latest"
uri="https://run.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/jobs/$TRAIN_JOB:run"
if gcloud scheduler jobs describe "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud scheduler jobs pause "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID"
  gcloud scheduler jobs update http "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID" \
    --schedule='*/5 * * * *' --time-zone=Asia/Tokyo --uri="$uri" --http-method=POST \
    --oauth-service-account-email="$scheduler" --oauth-token-scope=https://www.googleapis.com/auth/cloud-platform \
    --headers=Content-Type=application/json --message-body='{}'
else
  gcloud scheduler jobs create http "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID" \
    --schedule='*/5 * * * *' --time-zone=Asia/Tokyo --uri="$uri" --http-method=POST \
    --oauth-service-account-email="$scheduler" --oauth-token-scope=https://www.googleapis.com/auth/cloud-platform \
    --headers=Content-Type=application/json --message-body='{}'
  gcloud scheduler jobs pause "$SCHEDULE_NAME" --location="$SCHEDULER_REGION" --project="$PROJECT_ID"
fi
printf 'Deployed %s. Scheduler is paused: complete smoke tests, then run enable_schedule.sh.\n' "$image"
