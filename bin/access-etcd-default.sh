#!/usr/bin/env bash
set -e

kubectl config use-context secrets-default

kubectl exec -it -n kube-system etcd-minikube -- /bin/sh -c './etcdctl get /registry/secrets/default/demo'
