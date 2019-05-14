kubectl --context secrets-vault exec -n kube-system -it \
  etcd-minikube -- /bin/sh -c './etcdctl get /registry/secrets/default/demo'
