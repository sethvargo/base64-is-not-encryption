#!/usr/bin/env bash
set -Eeuo pipefail

gcloud builds submit \
  --project vargolabs \
  --tag gcr.io/vargolabs/k8s-cloud-kms-plugin \
  .
