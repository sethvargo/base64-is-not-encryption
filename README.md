# Base64 is not encryption

This document describes the steps for my demo to showcase how Kubernetes secrets
are inherently insecure by default.

You probably want to check out the [`tutorial`](tutorial) folder instead.

## Setup

1. Configure everything:

    ```text
    $ ./bin/setup.sh
    ```

## Demo

### Default secrets

```text
./bin/create-secret-default.sh
```

```text
./bin/access-etcd-default.sh
```

## Encrypted envelope

```text
./bin/create-secret-vault.sh
```

```text
./bin/access-etcd-vault.sh
```

## Destroy

1. Destroy everything:

    ```text
    $ ./bin/destroy.sh
    ```
