# VM platform

## Status — 2026-11-22

Step 3 is implemented and deployed on all three hypervisors using microvm.nix,
pinned in `flake.lock` and following the existing NixOS 26.05 package set.
**Only one empty base VM is enabled:** `hgd1-k8m01` on `hgd1-hv01`.
No k3s service/cluster has been installed; that is step 4.

Verified on the live VM:

- Key-only SSH at `10.10.40.11`; storage NIC `10.10.30.21`.
- Linux 7.3.4, DNS/internet and time from the K8S gateway, storage pings to all hosts.
- A marker in `/var/lib` and its SSH host key survived an actual VM restart.
- Host deployment changed the current runner without restarting the active VM
  (same QEMU PID; old `booted` runner retained until an explicit restart).
- Guest attempts to bypass router policy at L2 could not reach management SSH
  on any hypervisor through either guest-facing bridge. Guest SSH is also
  closed on its storage NIC.
- Host kernels remain 6.18.63. No hypervisor reboot or HDD initialization was
  needed; extended HDD tests continued.

**Hardware prerequisite:** hv01 and hv03 expose VT-x and `/dev/kvm`; hv02 does
not currently expose VMX/KVM. After its HDD test finishes, enable Intel
virtualization in its BIOS, verify `/dev/kvm`, and change
`hosts.hgd1-hv02.kvmAvailable` to true before enabling guests there. No slow
software-emulation fallback is provisioned in place of that hardware fix.

## Source of truth

| File | Responsibility |
| --- | --- |
| `inventory.nix` → `vms` | Host placement, enabled flag, role, CPU, RAM, disk size, ID and both static IPs |
| `modules/vm-lib.nix` | Stable MACs and TAP names from the numeric ID |
| `modules/hypervisor.nix` | Enabled guests on each host, bridge attachment, resource/identity assertions, isolation |
| `modules/vm-guest.nix` | Base NixOS, dual-NIC networking, persistent volume, SSH and read-only store |
| `scripts/vm.sh` | Inventory/key-checked lifecycle operations |

All five future guests have flake outputs and inventory entries; four remain
disabled until step 4:

| VM | Placement | Enabled | K8S IP | Storage IP | CPU / RAM / initial disk |
| --- | --- | --- | --- | --- | --- |
| hgd1-k8m01 | hv01 | yes | 10.10.40.11 | 10.10.30.21 | 2 / 4096 MiB / 60 GiB |
| hgd1-k8m02 | hv02 | no | 10.10.40.12 | 10.10.30.22 | 2 / 4096 MiB / 60 GiB |
| hgd1-k8m03 | hv03 | no | 10.10.40.13 | 10.10.30.23 | 2 / 4096 MiB / 60 GiB |
| hgd1-k8w01 | hv01 | no | 10.10.40.21 | 10.10.30.31 | 4 / 4096 MiB / 60 GiB |
| hgd1-k8w02 | hv02 | no | 10.10.40.22 | 10.10.30.32 | 4 / 4096 MiB / 60 GiB |

Static addresses are reserved by inventory, not DHCP leases: VLANs 30 and 40
have no DHCP service. VM IDs must remain stable/unique because they determine
the MACs/TAP names. Enabled guest RAM is limited to 11 GiB per host, reserving
roughly 4 GiB or more for the host/Ceph. Disk images are sparse; logical size
is not the same as allocated NVMe space.

## Storage and networking

Each VM's only writable data disk is:

```text
/var/lib/microvms/<name>/var-lib.img
```

It lives on the host's existing ext4 **NVMe** root, not on a Ceph HDD. The VM
mounts it at `/var/lib`; this preserves future k3s state, data and
`/var/lib/ssh/ssh_host_ed25519_key`. Runtime disks/private keys are not Git/Nix
store content. The rest of the base OS is disposable, with `/nix/store` shared
read-only over virtiofs. Deploy through the host, not by rebuilding the guest
imperatively. Changing `diskGB` changes initial creation size only: it does not
resize an existing image. Never shrink/truncate an existing filesystem.

Two root-managed TAPs join the already configured bridges:

- `tap<ID>-k8s` → `br-k8s` → tagged VLAN 40. Guest name `k8s`, default
  route/DNS/NTP `10.10.40.1`, management SSH permitted here.
- `tap<ID>-stor` → `br-stor` → tagged VLAN 30. Guest name `storage`, connected
  storage route only; no gateway/DNS and no SSH entrypoint.

NIC names match MACs, not probe order. The host's management SSH is allowed
only on its physical INFRA NIC; INPUT on the unnumbered K8S bridge and routing
between the guest-facing bridges and other interfaces are blocked. Normal L2
traffic on either bridge is unaffected. The qemu bridge-helper wildcard ACL
is denied; the platform uses its declared TAPs instead.

## Operate

From the laptop repo (set `JUMP` only while using bootstrap home access):

```sh
export JUMP=root@192.168.2.12
scripts/vm.sh list
scripts/vm.sh hgd1-k8m01 status
scripts/vm.sh hgd1-k8m01 logs
ssh -J "$JUMP" jurre@10.10.40.11
scripts/vm.sh hgd1-k8m01 restart
```

`vm.sh` verifies the hypervisor's SSH host key against inventory. `start`,
`stop`, and `restart` operate systemd; they never define/delete a disk. A
stopped enabled guest autostarts after the next host reboot. These commands
do **not** drain k3s or check etcd quorum: add those safeguards in step 4
before treating them as safe workload maintenance.

On the hypervisor, the underlying unit is `microvm@<name>.service`.

## Deploy/update

1. Edit inventory/guest modules and validate with `nix flake check --no-build`.
2. Review and commit; `scripts/deploy.sh` requires a clean tree.
3. Deploy the owning hypervisor: `scripts/deploy.sh hgd1-hv01 switch`.
4. Confirm a fresh SSH login to the host and inspect guest service health.
5. A changed guest **does not restart automatically** (`restartIfChanged = false`).
   Restart that guest deliberately when safe, then verify its IP, SSH identity
   and persisted data.

`/var/lib/microvms/<name>/current` points to the newly installed runner;
`booted` points to the runner actually in use and protects it from garbage
collection. A host deploy is not evidence that the live guest has already
booted the new OS. Do not use an old running guest's console as proof of a
new runner until explicitly restarted.

For a new guest, read the **public** `VM_HOST_KEY <name> ...` report from the
trusted hypervisor journal, compare/pin that public key, then connect with
strict SSH host-key checking. Never copy private host keys into inventory.
The current test VM's public key is recorded in `inventory.nix`.

Disabling/removing/moving a VM does not constitute a disk backup or safe live
migration. Stop the old instance explicitly, verify it stopped, and protect its
NVMe volume before changing placement. Never run two copies of a writable
image. k3s member removal and workload migration are separate step-4 procedures.

## Acceptance check

Write a non-secret marker to `/var/lib`, record its contents and the guest SSH
public-key fingerprint, and `sync`. Restart the VM, then verify:

- Boot ID changed, marker contents and SSH fingerprint did not.
- `/var/lib` is the ext4 virtio disk; default route exists only on `k8s`.
- No failed units; storage peers and gateway time/internet remain reachable.
- A host redeploy leaves the guest PID/boot ID unchanged until an explicit
  VM restart. Do not reboot a physical host during HDD qualification.
