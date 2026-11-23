---
icon: lucide/rocket
---

# Deploy a change

Every change follows the same loop: edit, validate, commit, deploy one host,
verify, next host. Deploys are manual and deliberately one host at a time.

## Before you start

- [Access](../get-started/access.md) works: `ssh jurre@10.10.20.11` without a
  password.
- You're in `nix develop`.
- `git status` shows only your own change.

## Steps

1. **Validate.** Flakes only see files Git knows about, so stage first:

    ```sh
    git add -A
    git diff --cached
    nix flake check --no-build
    nix build --no-link .#nixosConfigurations.hgd1-hv01.config.system.build.toplevel
    ```

    `flake check` evaluates every host and VM and runs the inventory checks.
    `nix build` builds one host's system without activating it; build every
    host your change affects.

2. **Commit.** The deploy script refuses a dirty tree.

    ```sh
    git commit -m "Describe the change"
    ```

3. **Preview** on the first host:

    ```sh
    deploy hgd1-hv01 dry-activate
    ```

4. **Deploy** it:

    ```sh
    deploy hgd1-hv01 switch
    ```

5. **Verify** with a **new** SSH connection:

    ```sh
    labctl health        # all ok (exit code 0)
    ```

    Also test the service you changed and read its logs.

6. **Repeat** steps 3–5 for `hgd1-hv02` and `hgd1-hv03`.
7. **Push:** `git push`.
8. **VM changes?** A deploy never restarts VMs. Boot them into the new
   version with [Restart k3s nodes](restart-k3s-nodes.md).

!!! warning "Known issue: Ceph heartbeats after the first clusterd rollout"

    On 2026-11-23 the first deploy of clusterd (which also reloaded the host
    firewall and added a Keepalived instance) was followed by about 12
    minutes of OSD heartbeat failures on hv01 and hv02 and a `SLOW_OPS`
    warning. No OSD went down and it cleared by itself. Later deploys,
    including other firewall reloads, didn't do this; the cause isn't known
    yet. After a deploy, check `labctl status ceph` before the next host.

## Actions

| Action | Effect |
| --- | --- |
| `dry-activate` | Build and show which units would restart; change nothing |
| `switch` | Activate now and boot into it from now on |
| `boot` | Boot into it next time; leave the running system alone |
| `test` | Activate now but keep the old boot default |

## Options

| Variable | Use |
| --- | --- |
| `TARGET=<addr>` | Connect to another address, e.g. a temporary DHCP lease during a rebuild |
| `JUMP=<user@addr>` | Go through an SSH jump host; only needed before remote access exists |
| `ALLOW_DIRTY=1` | Deploy uncommitted changes; avoid it |
| `SSH_USER` | Log in as someone other than `jurre` |

## Good to know

- The script checks the host's SSH key against the inventory first; a
  mismatch means the wrong or a reinstalled machine.
- The **host builds its own system** and fetches from the binary cache; the
  laptop only evaluates. `jurre` isn't a Nix trusted user on the hosts
  (that would be root-equivalent), so laptop-built closures would be refused.
- `dry-activate` isn't a safety test. Kernel changes need a reboot. With SSH,
  firewall or network changes, keep a second session open and know how to
  reach the console.

## If it goes wrong

[Roll back](roll-back.md).
