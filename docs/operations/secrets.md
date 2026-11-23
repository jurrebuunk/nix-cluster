# Secrets

Secrets are encrypted with [agenix](https://github.com/ryantm/agenix) and live
in `secrets/` as `*.age` files. Each one is encrypted to my laptop's SSH key
and to the SSH host keys of all three hypervisors. A host decrypts its secrets
during activation into `/run/agenix/` (or a path the module chooses), readable
only by root unless configured otherwise.

## The secrets

| File | Used by | Decrypted to |
| --- | --- | --- |
| `cloudflared-tunnel.age` | `cloudflared` tunnel credentials | `/run/agenix/cloudflared-tunnel` |
| `s3-acme-cloudflare.age` | Cloudflare API token for DNS-01 | `/run/agenix/s3-acme-cloudflare` |
| `k3s-server-token.age` | k3s server join token | `/run/k3s-secrets/server/server-token` (shared into server VMs) |
| `k3s-agent-token.age` | k3s agent join token | `/run/k3s-secrets/{server,agent}/agent-token` |

The recipients are defined in `secrets/secrets.nix`, which reads the keys from
`inventory.nix` (`adminKeys` plus every `hosts.*.hostKey`).

## What never goes in Git

- Passwords, API tokens, private keys and the k3s tokens in plain text.
- The kubeconfig (cluster-admin certificate).
- Ceph keyrings and S3 credentials; they live only on the hosts.
- Router and switch configuration exports (password hashes and keys).

If a secret ever lands in a commit, treat it as leaked: rotate it, then
clean up.

## Editing or adding a secret

```sh
nix develop
cd secrets
agenix -e cloudflared-tunnel.age          # opens $EDITOR with the decrypted content
```

To add one:

1. Add `"my-secret.age".publicKeys = all;` to `secrets/secrets.nix`.
2. `agenix -e my-secret.age` and type or paste the value.
3. Reference it in a module: `age.secrets.my-secret.file = ../secrets/my-secret.age;`
   and use `config.age.secrets.my-secret.path`.
4. Commit and deploy.

To put a file or a generated value in, without it ever appearing on screen,
encrypt straight from a pipe:

```sh
R=$(mktemp)
nix eval --raw --impure --expr \
  'builtins.concatStringsSep "\n" (import ./secrets.nix)."my-secret.age".publicKeys' > "$R"
openssl rand -hex 32 | tr -d '\n' | age -e -R "$R" -o my-secret.age
rm "$R"
```

!!! warning "Don't use a copy command as EDITOR"

    `EDITOR="cp file" agenix -e` looks handy but produced an **empty**
    secret here. Use the `age -R` pipe above, and check the result by
    decrypting it to a hash: `age -d -i ~/.ssh/id_ed25519 my-secret.age | sha256sum`.

## When a host key changes

After a reinstall, a host has a new SSH host key and can no longer decrypt
anything:

1. Put the new public key (`/etc/ssh/ssh_host_ed25519_key.pub`) in
   `inventory.nix`.
2. `cd secrets && agenix -r` re-encrypts every secret to the new recipients.
   This needs my laptop key.
3. Commit and deploy.

`scripts/deploy.sh` refuses to deploy to a host whose key doesn't match the
inventory, so you can't forget step 1.

## Rotating

| Secret | How |
| --- | --- |
| Tunnel credentials | Create a new tunnel or credentials in Cloudflare, re-encrypt, deploy all hosts, then remove the old ones |
| Cloudflare DNS token | Create a token limited to DNS edit on the zone, re-encrypt, deploy, check a renewal, then revoke the old one |
| k3s tokens | Changing the server token of a running cluster needs `k3s token rotate`; read the k3s docs first. The agent token can be replaced and agents restarted |
| S3 user keys | `radosgw-admin key create` for a new key, update the app, then remove the old key |
