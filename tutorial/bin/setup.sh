#!/usr/bin/env bash
set -Eeuo pipefail

source "$(cd "$(dirname "${0}")" &>/dev/null && pwd)/__helpers.sh"

gcloud services enable --project="$(google-project)" \
  cloudkms.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com

gcloud iam service-accounts create kubernetes \
  --project="$(google-project)" \
  --display-name="kubernetes"
SA_EMAIL="kubernetes@$(google-project).iam.gserviceaccount.com"

gcloud kms keyrings create kubernetes \
  --project="$(google-project)" \
  --location="$(google-region)"

gcloud kms keys create kubernetes-secrets \
  --project="$(google-project)" \
  --location="$(google-region)" \
  --purpose="encryption" \
  --keyring="kubernetes"

gcloud kms keys add-iam-policy-binding kubernetes-secrets \
  --project="$(google-project)" \
  --location="$(google-region)" \
  --keyring="kubernetes" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

gcloud compute instances create "kubernetes" \
  --boot-disk-size="500GB" \
  --can-ip-forward \
  --image-family="ubuntu-1804-lts" \
  --image-project="ubuntu-os-cloud" \
  --machine-type="n1-standard-4" \
  --metadata="enable-oslogin=TRUE" \
  --metadata-from-file="startup-script=scripts/startup.sh" \
  --network-tier="PREMIUM" \
  --project="$(google-project)" \
  --scopes="cloud-platform" \
  --service-account="${SA_EMAIL}" \
  --zone="$(google-zone)"
