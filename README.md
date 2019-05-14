# Base64 is not encryption

This document describes the steps for my demo to showcase how Kubernetes secrets are inherently insecure by default.

## Setup

1. Configure everything:

    ```text
    $ ./bin/setup.sh
    ```

## Demo

### Default secrets

```
./bin/create-secret-default.sh
```

```
./bin/access-etcd-default.sh
```

## Encrypted envelope

```
./bin/create-secret-vault.sh
```

```
./bin/access-etcd-vault.sh
```

## Destroy

1. Destroy everything:

    ```text
    $ ./bin/destroy.sh
    ```
