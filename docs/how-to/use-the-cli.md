---
icon: lucide/square-terminal
---

# Use the CLI

`labctl` is the command-line client for the [Platform API](../concepts/api.md),
built in the [`clusterd`](https://github.com/jurrebuunk/clusterd) repo next to
the server (two programs, one repo). The name isn't tied to this site: it
keeps one context per site, like kubeconfig.
platform status, metrics, logs and actions from your terminal, for daily
management and while developing. Every command is in the
[CLI reference](../reference/cli.md).

<span class="status status--partial">In development</span>

## Before you start

- WARP connected (or a cable into the management VLAN).
- `labctl` installed: in this repo's dev shell, ad hoc with
  `nix run github:jurrebuunk/clusterd#labctl -- <command>`, or permanently on
  the laptop through the `clusterd` flake input of `~/nixos` (see the
  [CLI reference](../reference/cli.md#install)).
- An API token (below).

## Tokens

Tokens are created by someone who can deploy the hosts, because their hashes
live in an agenix secret.

1. Create the token and its hash:

    ```sh
    labctl token new --name laptop-jurre --scope manage
    # prints the token once, and a hash line for the secret
    ```

2. Add the hash line to the secret and deploy the hosts:

    ```sh
    cd secrets && agenix -e api-tokens.age && cd ..
    git commit -am "API: token for laptop-jurre"
    scripts/deploy.sh hgd1-hv01 switch    # then hv02, hv03
    ```

3. Log in on the client; the token is stored in `~/.config/labctl/token`
   (mode 600):

    ```sh
    labctl login
    ```

Use `--scope read` for tokens that only look (dashboards, scripts) and
`--scope operator` for the web UI's proxy. Revoke a token by removing its line
from the secret and deploying.

## Steps

```sh
labctl status                                   # hosts, VMs, k3s, Ceph, VIPs at a glance
labctl metrics query 'smartctl_device_percentage_used'
labctl logs --host hgd1-hv01 --unit ceph-osd-0.service --since 1h
labctl logs --follow --host hgd1-fw01           # live router log
```

Actions need a `manage` token and ask for confirmation:

```sh
labctl vm restart hgd1-k8w01                    # drain → restart → Ready → uncordon
```

## Check it worked

```sh
labctl whoami        # token name and scope
labctl status        # everything green
```

## Good to know

- Output is a table by default; add `--json` for scripts.
- `LABCTL_API` overrides the endpoint (default `https://api.lan.buunk.org`),
  handy when developing `clusterd` against a single host.
- If a command fails with a connection error, check WARP first.
- Working on the CLI itself (new commands, bugs): that happens in the
  [`clusterd`](https://github.com/jurrebuunk/clusterd) repo.
