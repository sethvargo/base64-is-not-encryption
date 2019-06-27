#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f /etc/cloud-init/finished ]; then
  echo "already ran startup script"
  exit 0
fi

aptq-get() {
  DEBIAN_FRONTEND=noninteractive \
    apt-get -yqq -o=Dpkg::Use-Pty=0 "$@" \
    2>&1
}

# Common
aptq-get update
aptq-get upgrade
aptq-get autoremove
aptq-get autoclean
aptq-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common

# Swap
sed -i '/ swap / s/^/#/' /etc/fstab
swapoff -a

# Docker
aptq-get --purge remove docker docker-engine docker-ce docker.io runc
aptq-get clean
rm -rf /var/lib/docker
curl -sfsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
aptq-get update
aptq-get install --fix-broken docker-ce docker-ce-cli containerd.io

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker

# Kubernetes
aptq-get --purge remove kubelet kubeadm kubectl kubernetes-cni || true
curl -sLf https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat > /etc/apt/sources.list.d/kubernetes.list <<"EOF"
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
aptq-get update
aptq-get install kubelet kubeadm kubectl kubernetes-cni
aptq-get upgrade

kubeadm reset --force
kubeadm init \
  --apiserver-advertise-address="0.0.0.0" \
  --kubernetes-version="1.15.0" \
  --pod-network-cidr="192.168.0.0/16"

cat > /etc/profile.d/kubeadm.sh <<"EOF"
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF
source /etc/profile.d/kubeadm.sh
chmod 0644 /etc/kubernetes/admin.conf

# Install calico
kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml
kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml

# Allow scheduling on the master
kubectl taint nodes --all node-role.kubernetes.io/master-

# Helper to access etcd data
cat > /usr/local/bin/etcdctl <<"EOF"
ARGS="$@"

NAME="$(kubectl get po -l component=etcd -n kube-system -ojsonpath='{.items[0].metadata.name}')"

kubectl exec -n=kube-system -it "${NAME}" -- \
  /bin/sh -c "ETCDCTL_API=3 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key /usr/local/bin/etcdctl ${ARGS}"
EOF
chmod +x /usr/local/bin/etcdctl

# Encryption provider config (local key)
ENCRYPTION_KEY="$(head -c 32 /dev/urandom | base64)"
cat > /etc/kubernetes/pki/encryption-local.conf <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: "${ENCRYPTION_KEY}"
    - identity: {}
EOF
sudo sed -i '/- kube-apiserver/ a \ \ \ \ # - --encryption-provider-config=/etc/kubernetes/pki/encryption-local.conf' /etc/kubernetes/manifests/kube-apiserver.yaml

# Encryption provider config (kms key)
SOCKET_DIR="/etc/kubernetes/pki"
SOCKET_PATH="${SOCKET_DIR}/gcp-kms-plugin.sock"
mkdir -p "${SOCKET_DIR}"

PROJECT_ID="$(curl -sf -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)"
ZONE="$(basename $(curl -sf -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/instance/zone))"
REGION="${ZONE::-2}"

cat > /etc/systemd/system/gcp-kms-plugin.service <<EOF
Description=Google Cloud KMS plugin container
After=docker.service
Wants=network-online.target docker.socket
Requires=docker.socket

[Service]
Restart=always
ExecStartPre=/bin/bash -c "/usr/bin/docker container inspect gcp-kms-plugin 2> /dev/null || /usr/bin/docker run --name=gcp-kms-plugin --network=host --detach --volume=${SOCKET_DIR}:${SOCKET_DIR}:rw gcr.io/vargolabs/k8s-cloud-kms-plugin /k8s-cloud-kms-plugin --logtostderr --path-to-unix-socket=${SOCKET_PATH} --key-uri=projects/${PROJECT_ID}/locations/${REGION}/keyRings/kubernetes/cryptoKeys/kubernetes-secrets"
ExecStart=/usr/bin/docker start -a gcp-kms-plugin
ExecStop=/usr/bin/docker stop -t 10 gcp-kms-plugin

[Install]
WantedBy=multi-user.target
EOF
chmod 0755 /etc/systemd/system/gcp-kms-plugin.service

systemctl enable gcp-kms-plugin
systemctl start gcp-kms-plugin

cat > /etc/kubernetes/pki/encryption-kms.conf <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - kms:
        name: gcp-kms-plugin
        endpoint: unix://${SOCKET_PATH}
        cachesize: 100
    # We still need our old key here so older secrets can be decrypted!
    - aescbc:
        keys:
        - name: key1
          secret: "${ENCRYPTION_KEY}"
    - identity: {}
EOF

sudo sed -i '/- kube-apiserver/ a \ \ \ \ # - --encryption-provider-config=/etc/kubernetes/pki/encryption-kms.conf' /etc/kubernetes/manifests/kube-apiserver.yaml

# Slightly nicer login
touch ~/.hushlogin

# Mark done
mkdir -p /etc/cloud-init
touch /etc/cloud-init/finished

# Reboot
reboot
