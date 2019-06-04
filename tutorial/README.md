# Tutorial Mode

This tutorial walks you through installing and configuring an encryption
provider configuration for Kubernetes. It starts by showing the insecurities in
the default Kubernetes setup. Then, it explores a local encryption provider
configuration using a user-managed key. Finally, it explores an external KMS
plugin for encrypting Kubernetes secrets.


1. Create the instance. This tutorial uses a single VM that runs as both the
   Kubernetes master and node. This both simplifies the tutorial and reduces
   costs.

    ```text
    ./bin/setup.sh
    ```

    After the machine boots, it installs kubeadm and provisions a kubernetes
    cluster. This process can take up to 5 minutes, but it is usually complete
    in about one minute.

1. SSH into the VM named "kubernetes" (click SSH button in the browser). To
   verify everything is working correctly, run:

    ```text
    kubectl get po
    ```

1. To demonstrate the default Kubernetes setup insecurities, create a generic
   secret (you can replace these with your own values, but please do not use
   "real" passwords here):

    ```text
    kubectl create secret generic login \
      --from-literal=username=sethvargo \
      --from-literal=password=secretsauce
    ```

    This will create a Kubernetes secret named "login" with key-value pairs for
    "username" and "password".

1. In a default Kubernetes setup, secrets are stored in plaintext in etcd. If
   you are not familiar with etcd, you can think of it as a filesystem - it is
   where Kubernetes stores most of its data.

    When a secret is created, it is stored in **etcd in plaintext**. This means
    the secret is available if:

    - You expose your etcd cluster publicly (don't laugh)
    - An attacker gains access to a backup of etcd
    - An attacker gains access to a backup of the filesytem
    - An attacker gains live access to the VMs running Kubernetes

    To demonstrate this, query etcd for the value of the secret we just created:

    ```text
    etcdctl get /registry/secrets/default/login
    ```

    The data in the secret is available in plaintext in etcd.

1. To help mitigate this problem, Kubernetes 1.7 introduced an
   `EncryptionProviderConfiguration`, which allows for secrets to be encrypted
   using a local user-managed key before being stored in etcd. This tutorial
   creates such a configuration for you automatically. You can inspect its
   contents:

    ```text
    cat /etc/kubernetes/pki/encryption-local.conf
    ```

    This configuration tells Kubernetes (specifically it tells the
    kubeapi-server) to encrypt/decrypt secrets using the provided key. Old,
    unencrypted secrets will still be available because we added the `identity`
    provider (which is passthrough).

    Once we enable this configuration, secrets will no longer be written to etcd
    in plaintext.

1. To enable the encryption configuration, we must add the
   `--encryption-provider-config` flag to the kubeapi-server. The flags to start
   the kubeapi-server are defined in a manifest.

    Open this manifest in your text editor:

    ```text
    sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
    ```

    Uncomment the `--encryption-provider-config` for `encryption-local`. **Do
    not uncomment the configuration for encryption-kms yet**:

    ```text
    - --encryption-provider-config=/etc/kubernetes/pki/encryption-local.conf
    ```

    Save this file and wait. The kubelet will detect changes to this file and
    restart the kubeapi-server. You can watch these changes by inspecting the
    output at:

    ```text
    kubectl get po -n kube-system
    ```

1. Replace the secret we previously created. If setup correctly, the new values
   will be encrypted before being stored in etcd.

    ```text
    kubectl delete secret login
    ```

    ```text
    kubectl create secret generic login \
      --from-literal=username=sethvargo \
      --from-literal=password=secretsauce
    ```

1. Check the value in etcd and note that it is no longer in plaintext:

    ```text
    etcdctl get /registry/secrets/default/login
    ```

    This improves our security posture because it limits an attacker's ability
    when given direct access to etcd. However, we have not improved our security
    as much as we would like:

    - ~~You expose your etcd cluster publicly (don't laugh)~~
    - ~~An attacker gains access to a backup of etcd~~
    - An attacker gains access to a backup of the filesytem
    - An attacker gains live access to the VMs running Kubernetes

    If an attacker gains access to filesystem (either directly or a backup), the
    encryption keys are stored in that YAML file in plaintext.

1. To best improve our security posture, we need to leverage a feature introduce
   in Kubernetes 1.10 - KMS provider plugins. By leveraging a third-party KMS
   plugin, we separate where keys are stored from where keys are accessed. We
   require an attacker compromise two systems.

    Similar to the previous example, we need to create an
    `EncryptionProviderConfig` to use the KMS plugin. This tutorial creates such
    a configuration for you automatically. You can inspect its contents:

    ```text
    cat /etc/kubernetes/pki/encryption-local.conf
    ```

    Notice that this configuration does not include any encryption keys. That is
    because KMS manages the encryption keys.

    Like previously, To enable the encryption configuration, we must add the
   `--encryption-provider-config` flag to the kubeapi-server. Open the manifest
   in your text editor:

    ```text
    sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
    ```

    1. Delete the old `--encryption-provider-config` for `encryption-local`
    1. Uncomment the `--encryption-provider-config` for `encryption-kms`

    ```text
    - --encryption-provider-config=/etc/kubernetes/pki/encryption-kms.conf
    ```

    Save this file and wait. The kubelet will detect changes to this file and
    restart the kubeapi-server. You can watch these changes by inspecting the
    output at:

    ```text
    kubectl get po -n kube-system
    ```

1. Replace the secret we previously created. If setup correctly, the new values
   will be encrypted with a KMS-managed key before being stored in etcd.

    ```text
    kubectl delete secret login
    ```

    ```text
    kubectl create secret generic login \
      --from-literal=username=sethvargo \
      --from-literal=password=secretsauce
    ```

1. Check the value in etcd and note that it is no longer in plaintext:

    ```text
    etcdctl get /registry/secrets/default/login
    ```

    This improves our security posture because it limits an attacker's ability
    when given direct access to etcd or a backup of our filesystem:

    - ~~You expose your etcd cluster publicly (don't laugh)~~
    - ~~An attacker gains access to a backup of etcd~~
    - ~~An attacker gains access to a backup of the filesytem~~
    - An attacker gains live access to the VMs running Kubernetes

    This still has not mitigated live access to the VMs running Kubernetes. One
    might argue that such a thing would be outside of a typical threat model.
    However, it is worth nothing that the KMS approach his _improved_ this
    attack vector while not fully mitigating it. Because keys are stored in a
    separate location (and access is managed via IAM), an attacker requires
    online access to the KMS service. If logs or anomoly software detects
    abnormal use of a key, this can be flagged and access can be revoked to
    limit the surface of the breach.
