---
icon: lucide/rocket
---

# Get started

Three short steps take you from nothing to a deployed change. Do them in
order the first time.

<div class="grid cards" markdown>

-   :lucide-log-in:{ .lg .middle } **1. Get access**

    ---

    Connect WARP, log in to a host and a VM, and get a kubeconfig.

    [:octicons-arrow-right-24: Get access](access.md)

-   :lucide-git-commit-horizontal:{ .lg .middle } **2. Your first change**

    ---

    Make a harmless change, validate it, deploy it to one host and roll it out.

    [:octicons-arrow-right-24: First change](first-change.md)

-   :lucide-folder-git-2:{ .lg .middle } **3. Tour of the repo**

    ---

    Where everything is configured, and the conventions to follow.

    [:octicons-arrow-right-24: Repository](repository.md)

</div>

## What you need

- A Linux or macOS machine with [Nix](https://nixos.org/download/) and flakes
  enabled.
- An SSH key that is listed in `inventory.nix` → `adminKeys`.
- A device enrolled in the Cloudflare Zero Trust team `buunk`, or a cable
  into the site network.
- A clone of the repo:

    ```sh
    git clone https://github.com/jurrebuunk/nix-hgd1-cluster
    cd nix-hgd1-cluster
    nix develop
    ```

`nix develop` gives you every tool these docs use: `nixos-rebuild`, `agenix`,
`cloudflared`, `kubectl`, the `labctl` CLI, `jq`, `nmap`, `shellcheck` and
`zensical`, plus the repo's scripts as short commands: `deploy`,
`kubeconfig` and `ceph-bootstrap` (see [Scripts](../reference/scripts.md)).

## Then read

- [Architecture](../concepts/index.md): the big picture, once, before you
  change anything substantial.
- [Health check](../operate/index.md): the five-minute check you'll run most.
