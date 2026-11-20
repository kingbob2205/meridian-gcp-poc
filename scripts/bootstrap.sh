#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for Meridian Payments GCP POC:
# Creates the isolated GCP project, links billing, enables bootstrap APIs,
# and provisions the versioned, uniform-access GCS bucket for Terraform remote state.

PROJECT_ID="${1:-meridian-gcp-poc-ho26}"
BILLING_ACCOUNT="${2:?Usage: $0 <PROJECT_ID> <BILLING_ACCOUNT_ID>}"
REGION="${3:-europe-west3}"
STATE_BUCKET="gs://${PROJECT_ID}-tfstate"

echo "==> Ensuring GCP project ${PROJECT_ID} exists..."
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud projects create "${PROJECT_ID}" --name="Meridian GCP POC" --quiet
fi

echo "==> Linking billing account ${BILLING_ACCOUNT}..."
gcloud billing projects link "${PROJECT_ID}" \
  --billing-account="${BILLING_ACCOUNT}" \
  --quiet

echo "==> Enabling bootstrap APIs..."
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

echo "==> Creating Terraform remote state bucket ${STATE_BUCKET} in ${REGION}..."
if ! gcloud storage buckets describe "${STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --quiet
fi

echo "==> Enabling object versioning on ${STATE_BUCKET}..."
gcloud storage buckets update "${STATE_BUCKET}" \
  --versioning \
  --quiet

echo "==> Bootstrap complete. Remote state bucket: ${STATE_BUCKET}"
