# nix-hgd1-cluster

NixOS configuration for my homelab at site `hgd1`: three small x86 nodes
(`hgd1-hv01..03`) running Ceph on their HDDs and a k3s cluster on microVMs,
plus the documentation for the OPNsense/Aruba site network around them.

**Documentation: <https://jurrebuunk.github.io/nix-hgd1-cluster/>**

It explains the architecture, the network, storage, VMs and Kubernetes, how
to build on top of the platform and how to maintain it. The source is in
[`docs/`](docs/).

## Quick facts

| | |
| --- | --- |
| Hosts | `hgd1-hv01..03` at `10.10.20.11–13`, NixOS 26.05 |
| Storage | Ceph 20, three replicas; S3 at `https://s3.lan.buunk.org` |
| Kubernetes | k3s, API `https://k8s.lan.buunk.org:6443` |
| Source of truth | [`inventory.nix`](inventory.nix) |
| Deploy | `scripts/deploy.sh <host> switch`, one host at a time |
| Access | Cloudflare WARP, then `ssh jurre@10.10.20.11` |

## Working on the docs

```sh
nix develop
zensical serve      # http://localhost:8000
```

Pushing to `main` publishes the site through GitHub Actions.
