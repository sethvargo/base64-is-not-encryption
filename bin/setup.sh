#!/usr/bin/env bash
set -e

rm -rf ~/.minikube/{machines,profiles}
rm -rf ~/.kube/config

minikube start \
  --profile=secrets-default \
  --cpus=2 \
  --memory=4096 \
  --vm-driver=hyperkit

minikube start \
  --profile=secrets-vault \
  --cpus=2 \
  --memory=4096 \
  --vm-driver=hyperkit

minikube ssh -p=secrets-vault "$(cat ./bin/bootstrap.sh)"

sleep 10

kubectl --context=secrets-default exec -it -n kube-system etcd-minikube -- /bin/sh -c 'cat <<"EOF" > ./etcdctl
export ETCDCTL_API=3
export ETCDCTL_CACERT=/var/lib/minikube/certs/etcd/ca.crt
export ETCDCTL_CERT=/var/lib/minikube/certs/etcd/server.crt
export ETCDCTL_KEY=/var/lib/minikube/certs/etcd/server.key
exec /usr/local/bin/etcdctl "$@"
EOF
chmod +x ./etcdctl'

kubectl --context=secrets-vault exec -it -n kube-system etcd-minikube -- /bin/sh -c 'cat <<"EOF" > ./etcdctl
export ETCDCTL_API=3
export ETCDCTL_CACERT=/var/lib/minikube/certs/etcd/ca.crt
export ETCDCTL_CERT=/var/lib/minikube/certs/etcd/server.crt
export ETCDCTL_KEY=/var/lib/minikube/certs/etcd/server.key
exec /usr/local/bin/etcdctl "$@"
EOF
chmod +x ./etcdctl'
