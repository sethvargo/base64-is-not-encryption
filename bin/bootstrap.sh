#!/usr/bin/env bash
set -e

# Install Vault
curl -sfLo vault.zip https://releases.hashicorp.com/vault/1.1.2/vault_1.1.2_linux_amd64.zip
unzip vault.zip
sudo mv vault /usr/bin/
sudo chmod +x /usr/bin/vault

# Setup profile
cat <<EOF | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR=http://127.0.0.1:8200
EOF
source /etc/profile.d/vault.sh

# Add Vault user
sudo adduser -S -s /bin/false -D vault

# Create Vault data
sudo mkdir -p /etc/vault/{config,data}

cat <<EOF | sudo tee /etc/vault/config/config.hcl
disable_mlock = "true"

backend "file" {
  path = "/etc/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}
EOF

sudo chown -R vault:vault /etc/vault

# Setup systemd
cat <<"EOF" | sudo tee /etc/systemd/system/vault.service
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault/config
ExecReload=/bin/kill --signal HUP $MAINPID
ExecStartPost=-/bin/sh -c "/bin/sleep 5 && /bin/vault operator unseal -address=http://127.0.0.1:8200 $(/bin/cat /etc/vault/init.json | /bin/jq -r .unseal_keys_hex[0])"
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start vault


# Init vault
vault operator init -format=json -key-shares=1 -key-threshold=1 | sudo tee /etc/vault/init.json
vault operator unseal "$(cat /etc/vault/init.json | jq -r .unseal_keys_hex[0])"
vault login "$(cat /etc/vault/init.json | jq -r .root_token)"
vault token create -id=vault-kms-k8s-plugin-token

# Create transit key
vault secrets enable transit
vault write -f transit/keys/my-key

# Install KMS plugin
curl -sfLo vault-k8s-kms-plugin.zip https://storage.googleapis.com/sethvargo-assets/vault-k8s-kms-plugin.zip
unzip vault-k8s-kms-plugin.zip
sudo mv vault-k8s-kms-plugin /bin/vault-k8s-kms-plugin
sudo chmod +x /bin/vault-k8s-kms-plugin

sudo mkdir -p /etc/vault-k8s-kms-plugin

# Configure KMS plugin
cat <<EOF | sudo tee /etc/vault-k8s-kms-plugin/config.yaml
keyNames:
- my-key
transitPath: /transit
addr: http://127.0.0.1:8200
token: vault-kms-k8s-plugin-token
EOF

sudo chown -R vault:vault /etc/vault-k8s-kms-plugin

# Setup systemd
cat <<EOF | sudo tee /etc/systemd/system/vault-k8s-kms-plugin.service
[Unit]
Description="KMS transit plugin"
Requires=vault.service
After=vault.service

[Service]
User=root
Group=root
ExecStart=/usr/bin/vault-k8s-kms-plugin -socketFile=/var/lib/minikube/certs/vault-k8s-kms-plugin.sock -vaultConfig=/etc/vault-k8s-kms-plugin/config.yaml
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start vault-k8s-kms-plugin


# Configure encryption config
cat <<EOF | sudo tee /var/lib/minikube/certs/encryption-config.yaml
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
- resources:
  - secrets
  providers:
  - kms:
      name: vault
      endpoint: unix:///var/lib/minikube/certs/vault-k8s-kms-plugin.sock
      cachesize: 100
  - identity: {}
EOF

sudo sed -i '/- kube-apiserver/ a \ \ \ \ - --encryption-provider-config=/var/lib/minikube/certs/encryption-config.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml

sudo systemctl daemon-reload
sudo systemctl stop kubelet
docker stop $(docker ps -aq)
sudo systemctl start kubelet
