---
icon: lucide/square-terminal
---

# Use the CLI

!!! repo "Lives in its own repo: clusterd"

    This page covers **using `labctl`** on the hgd1 cluster: how it fits in and how I
    use it here. Code, development, releases and the full documentation are in
    the repo.

    [:fontawesome-brands-github: jurrebuunk/clusterd](https://github.com/jurrebuunk/clusterd){ .md-button .md-button--primary }

`labctl` is the command-line client for the [Platform API](../concepts/api.md),
built in the [`clusterd`](https://github.com/jurrebuunk/clusterd) repo next to
the server (two programs, one repo). The name isn't tied to this site: it
keeps one context per site, like kubeconfig.
platform status, metrics, logs and actions from your terminal, for daily
management and while developing. Every command is in the
[CLI reference](../reference/cli.md).

<span class="status">v1.1.0</span>

## Before you start

- WARP connected on `hgd1-admin` (or a cable into the management VLAN).
- `labctl` installed: in this repo's dev shell, ad hoc with
  `nix run github:jurrebuunk/clusterd#labctl -- <command>`, or permanently on
  the laptop through the `clusterd` flake input of `~/nixos` (see the
  [CLI reference](../reference/cli.md#install)).
- An API token (below).

## Tokens

Tokens are created by someone who can deploy the hosts, because their hashes
live in an agenix secret.

1. Create the token straight into its file, so it never shows on screen;
   the command prints only the hash line:

    ```sh
    labctl auth token create --name laptop-jurre --scope manage --out ~/.config/labctl/tokens/hgd1
    # laptop-jurre manage sha256:…
    ```

    For a token that goes elsewhere (the web UI's Secret), use `--out` with a
    temporary file and delete it once it's stored.

2. Add the hash line to the secret and deploy the hosts. The deploy restarts
   `clusterd`, which loads the new list:

    ```sh
    cd secrets && agenix -e api-tokens.age && cd ..   # paste the line
    git commit -am "API: token for laptop-jurre"
    deploy hgd1-hv01 switch                          # then hv02, hv03
    ```

3. Log in on the client. This checks the token and stores it in
   `~/.config/labctl/tokens/hgd1` (mode 600):

    ```sh
    labctl auth login --token-file ~/.config/labctl/tokens/hgd1   # or: labctl auth login, and paste it
    ```

Use `--scope read` for tokens that only look (dashboards, scripts) and
`--scope operator` for the web UI's proxy. Revoke a token by removing its line
from the secret and deploying.

## Steps

```sh
labctl status                          # hosts, VMs, k3s, Ceph, VIPs at a glance
labctl health                          # one verdict per area
labctl host list                       # which commit each host runs, reboots pending
labctl pod list --failing              # pods that need a look
labctl operation list                  # what was done lately, by whom
labctl disk list                       # drives: size, how full, wear, SMART
labctl fs list                         # filesystems of hosts and VMs, how full
labctl s3 status                       # gateways, users, room left, certificate
labctl s3 bucket list                  # buckets: owner, size, quota
labctl logs --host hgd1-hv01 --unit ceph-osd-0.service --since 1h
labctl logs --follow --host hgd1-fw01  # live router log
```

Actions need at least an `operator` token and ask for confirmation:

```sh
labctl vm restart hgd1-k8w01 --dry-run          # what would happen
labctl vm restart hgd1-k8w01                    # cordon → drain → restart → Ready → uncordon
```

Output is compact, like `kubectl`:

```text
$ labctl node list
NODE        STATUS  ROLES               VERSION       ZONE
hgd1-k8m01  Ready   control-plane,etcd  v1.35.8+k3s1  hgd1-hv01
…
$ labctl vm restart hgd1-k8w02 --yes
node/hgd1-k8w02 cordoned
evicting pod kube-system/coredns-c5fdd76cf-5r4jq
node/hgd1-k8w02 drained
microvm@hgd1-k8w02 restarted on hgd1-hv03
node/hgd1-k8w02 Ready (new boot)
node/hgd1-k8w02 uncordoned
Kubernetes API ready
vm restart hgd1-k8w02 done
```

## Check it worked

```sh
labctl auth status  # token name and scope
labctl status       # everything green
```

## Good to know

- Commands are a noun and a verb (`labctl vm stop`, `labctl s3 bucket
  list`); `labctl <noun> --help` lists the verbs, and Tab completes them and
  the names of VMs, hosts and buckets.
- `--unit` takes a unit or syslog app name, with or without `.service`
  (`--unit clusterd`), or a prefix (`--unit 'ceph-osd*'`).
- Output is a table by default; `-o json` for scripts
  (`labctl -o json status | jq .ceph`), `-o name` for one name per line
  (`labctl vm list -o name`).
- Another site: `labctl auth login --site <name> --api https://…`, then
  `labctl site use <name>` or `--site <name>`.
- `LABCTL_API` overrides the endpoint (default `https://api.lan.buunk.org`),
  handy when developing `clusterd` against a single host.
- If a command fails with a connection error, check WARP first.
- Working on the CLI itself (new commands, bugs): that happens in the
  [`clusterd`](https://github.com/jurrebuunk/clusterd) repo.
