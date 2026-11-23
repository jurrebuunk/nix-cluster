---
icon: lucide/key-round
---

# Manage secrets

Secrets are [agenix](https://github.com/ryantm/agenix) files in `secrets/`,
encrypted to my laptop's SSH key and the three hosts' SSH host keys. Hosts
decrypt them at activation, readable by root only unless a module says
otherwise. The list of secrets is in [Files](../reference/files.md#secrets).

## Before you start

- You're in `nix develop` (for `agenix` and `age`).
- Your laptop key (`~/.ssh/id_ed25519`) is in `inventory.nix` → `adminKeys`.

## Edit a secret

```sh
cd secrets
agenix -e cloudflared-tunnel.age      # opens $EDITOR with the plain text
```

Commit and deploy the hosts that use it.

## Add a secret

1. Add it to `secrets/secrets.nix`:

    ```nix
    "my-secret.age".publicKeys = all;
    ```

2. Create it: `cd secrets && agenix -e my-secret.age`.
3. Use it in a module:

    ```nix
    age.secrets.my-secret.file = ../secrets/my-secret.age;
    # path at runtime: config.age.secrets.my-secret.path
    ```

4. Commit and deploy.

### From a pipe

To encrypt without the value ever appearing on screen:

```sh
cd secrets
R=$(mktemp)
nix eval --raw --impure --expr \
  'builtins.concatStringsSep "\n" (import ./secrets.nix)."my-secret.age".publicKeys' > "$R"
openssl rand -hex 32 | tr -d '\n' | age -e -R "$R" -o my-secret.age    # or: age -e -R "$R" -o my-secret.age < file
rm "$R"
```

!!! warning "Don't use a copy command as EDITOR"

    `EDITOR="cp file" agenix -e` produced an **empty** secret here. Use the
    pipe above, and check by hashing the decrypted value:
    `age -d -i ~/.ssh/id_ed25519 my-secret.age | sha256sum`.

## Re-key

A reinstalled host has a new SSH host key and can't decrypt anything:

1. Put its new public key (`/etc/ssh/ssh_host_ed25519_key.pub`) in
   `inventory.nix` → `hosts.<name>.hostKey`.
2. Re-encrypt everything: `cd secrets && agenix -r`.
3. Commit and deploy.

`scripts/deploy.sh` refuses a host whose key doesn't match, so you can't skip
step 1.

## Rotate

| Secret | How |
| --- | --- |
| Tunnel credentials | New credentials in Cloudflare, re-encrypt, deploy all hosts, then remove the old ones |
| Cloudflare DNS token | New token limited to DNS edit, re-encrypt, deploy, check a renewal, revoke the old one |
| k3s agent token | Replace the secret, deploy, restart the agents |
| k3s server token | Needs `k3s token rotate` on a running cluster; read the k3s docs first |
| S3 user keys | `radosgw-admin key create`, update the app, remove the old key |

## Never in Git

Passwords, tokens and private keys in plain text; the kubeconfig; Ceph
keyrings and S3 credentials; router and switch exports. If one ever lands in
a commit, treat it as leaked: rotate it first, then clean up.
