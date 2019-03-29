#!/usr/bin/env bash
set -e

kubectl config use-context secrets-default

kubectl create secret generic demo \
  --from-literal username=sethvargo \
  --from-literal password=s3cr3t
