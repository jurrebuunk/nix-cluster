---
icon: lucide/square-terminal
---

# Use the CLI

`hgd1` is the command-line client for the [Platform API](../concepts/api.md):
platform status, metrics, logs and actions from your terminal, for daily
management and while developing. Every command is in the
[CLI reference](../reference/cli.md).

<span class="status status--partial">In development</span>

## Before you start

- WARP connected (or a cable into the management VLAN).
- `nix develop` in this repo (`hgd1` is in the dev shell), or run it anywhere
  with `nix run github:jurrebuunk/nix-hgd1-cluster#hgd1 -- <command>`.
- An API token (below).

## Tokens

Tokens are created by someone who can deploy the hosts, because their hashes
live in an agenix secret.

1. Create the token and its hash:

    ```sh
    hgd1 token new --name laptop-jurre --scope manage
    # prints the token once, and a hash line for the secret
    ```

2. Add the hash line to the secret and deploy the hosts:

    ```sh
    cd secrets && agenix -e api-tokens.age && cd ..
    git commit -am "API: token for laptop-jurre"
    scripts/deploy.sh hgd1-hv01 switch    # then hv02, hv03
    ```

3. Log in on the client; the token is stored in `~/.config/hgd1/token`
   (mode 600):

    ```sh
    hgd1 login
    ```

Use `--scope read` for tokens that only look (dashboards, scripts). Revoke a
token by removing its line from the secret and deploying.

## Steps

```sh
hgd1 status                                   # hosts, VMs, k3s, Ceph, VIPs at a glance
hgd1 metrics query 'smartctl_device_percentage_used'
hgd1 logs --host hgd1-hv01 --unit ceph-osd-0.service --since 1h
hgd1 logs --follow --host hgd1-fw01           # live router log
```

Actions need a `manage` token and ask for confirmation:

```sh
hgd1 vm restart hgd1-k8w01                    # drain → restart → Ready → uncordon
```

## Check it worked

```sh
hgd1 whoami        # token name and scope
hgd1 status        # everything green
```

## Good to know

- Output is a table by default; add `--json` for scripts.
- `HGD1_API` overrides the endpoint (default `https://api.lan.buunk.org`),
  handy when developing `clusterd` against a single host.
- If a command fails with a connection error, check WARP first.
