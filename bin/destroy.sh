#!/usr/bin/env bash
set -e

minikube stop -p secrets-default &
minikube stop -p secrets-vault &
wait
