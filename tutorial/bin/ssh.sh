#!/usr/bin/env bash
set -Eeuo pipefail

source "$(cd "$(dirname "${0}")" &>/dev/null && pwd)/__helpers.sh"

exec gcloud compute ssh "kubernetes" \
  --project "$(google-project)" \
  --zone "$(google-zone)"
