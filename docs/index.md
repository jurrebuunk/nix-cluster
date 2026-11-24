---
icon: lucide/house
hide:
  - toc
---

# hgd1 Cluster

My homelab at site **hgd1**: three small x86 machines running NixOS, Ceph
storage, an S3 endpoint and the VMs of a k3s cluster. Everything here is
code in [`nix-hgd1-cluster`](https://github.com/jurrebuunk/nix-hgd1-cluster),
deployed from my laptop.

The homelab's docs are three sites, each covering only what its repo owns:

<div class="grid cards" markdown>

-   :lucide-server:{ .lg .middle } **Cluster** (you're here)

    ---

    Hosts, Ceph, S3, microVMs, the k3s nodes, monitoring, remote access, the
    Platform API and `labctl`.

-   :lucide-ship-wheel:{ .lg .middle } **Kubernetes**

    ---

    What runs on k3s: Flux, public access, Postgres, Keycloak, and how to run
    an app.

    [Kubernetes docs](https://jurrebuunk.github.io/hgd1-k8s/){ .md-button }

-   :lucide-network:{ .lg .middle } **Network**

    ---

    The OPNsense router, the Aruba switch, VLANs and the firewall between
    them.

    [Network docs](https://github.com/jurrebuunk/hgd1-network/blob/main/docs/index.md){ .md-button }

</div>

I wrote these docs mainly for myself, to maintain the setup months from now
without rediscovering it. They're also written so anyone can understand the
whole project, build on top of it or take over its maintenance.

<div class="grid cards" markdown>

-   :lucide-rocket:{ .lg .middle } **Get started**

    ---

    Get access, make your first change and find your way around the repo.

    [:octicons-arrow-right-24: Get started](get-started/index.md)

-   :lucide-lightbulb:{ .lg .middle } **Concepts**

    ---

    How the network, hosts, storage and Kubernetes fit together, and why.

    [:octicons-arrow-right-24: Concepts](concepts/index.md)

-   :lucide-wrench:{ .lg .middle } **How-to guides**

    ---

    Short, numbered steps for one task each: deploy, add a VM, add a secret.

    [:octicons-arrow-right-24: How-to](how-to/index.md)

-   :lucide-heart-pulse:{ .lg .middle } **Operate**

    ---

    Health checks, maintenance, troubleshooting and disaster recovery.

    [:octicons-arrow-right-24: Operate](operate/index.md)

-   :lucide-book-open:{ .lg .middle } **Reference**

    ---

    Every address, port, script, inventory field and term in one place.

    [:octicons-arrow-right-24: Reference](reference/index.md)

</div>

## At a glance

```mermaid
flowchart TB
  internet((Internet)) --- home[Home router<br/>192.168.2.0/24]
  home --- fw[OPNsense<br/>hgd1-fw01]
  fw --- sw[Aruba switch<br/>hgd1-sw01]
  sw --- hv01[hgd1-hv01] & hv02[hgd1-hv02] & hv03[hgd1-hv03]
  subgraph cluster [Three NixOS nodes]
    hv01
    hv02
    hv03
  end
  cluster --> ceph[(Ceph: RBD + S3)]
  cluster --> vms[microVMs<br/>k3s: 3 servers, 2 agents]
  vms --> ceph
  cluster --> mon[Monitoring<br/>mon.lan.buunk.org]
  laptop[Laptop + WARP<br/>labctl CLI, web UI] -. Cloudflare tunnel .-> api[Platform API<br/>api.lan.buunk.org]
  api --> cluster
```

| Layer | Status | Read |
| --- | --- | --- |
| Host network: one cable, VLANs and bridges | <span class="status">Done</span> | [Host network](concepts/network.md) |
| Remote access through Cloudflare | <span class="status">Done</span> | [Remote access](concepts/remote-access.md) |
| NixOS hosts `hgd1-hv01..03` | <span class="status">Done</span> | [Hosts](concepts/hosts.md) |
| Ceph with three replicas | <span class="status">Done</span> | [Ceph](concepts/ceph.md) |
| S3 at `https://s3.lan.buunk.org` | <span class="status">Done</span> | [S3 endpoint](concepts/s3.md) |
| microVMs | <span class="status">Done</span> | [VMs](concepts/vms.md) |
| k3s cluster: 3 servers, 2 agents | <span class="status">Done</span> | [k3s](concepts/k3s.md) |
| Monitoring and logs | <span class="status">Done</span> | [Monitoring](concepts/monitoring.md) |
| Platform API and CLI | <span class="status">Done</span> | [Platform API](concepts/api.md) |

## I want to…

| … | Go to |
| --- | --- |
| log in to a host or VM | [Get access](get-started/access.md) |
| change something and deploy it | [Deploy a change](how-to/deploy.md) |
| check or manage the platform from my terminal | [Use the CLI](how-to/use-the-cli.md) |
| run an app on the cluster | [Build an app](https://jurrebuunk.github.io/hgd1-k8s/how-to/build-an-app/) (Kubernetes docs) |
| check that everything is healthy | [Health check](operate/index.md) |
| reboot or service a host | [Host maintenance](operate/host-maintenance.md) |
| fix something that's broken | [Troubleshooting](operate/troubleshooting.md) |
| look up an IP address | [Addresses](reference/addresses.md) |
| change the router or switch | [Router and switch](https://github.com/jurrebuunk/hgd1-network/blob/main/docs/router-and-switch.md) (network docs) |
| work on the API, CLI or web UI | [`clusterd`](https://github.com/jurrebuunk/clusterd), [`lab-console`](https://github.com/jurrebuunk/lab-console) |
| see which repo owns what | [Repositories](reference/repositories.md) |
| find metrics or logs | [Monitoring](concepts/monitoring.md#operating) |
| find a credential | [Credentials](reference/credentials.md) |

## Conventions

- *I* is me, the owner. *You* is whoever does the work, usually also me.
- Commands run from the repository root on the laptop, with WARP connected,
  unless they say otherwise.
- `inventory.nix` is the source of truth. If the docs disagree with it, the
  docs are wrong.
- Secrets never appear in the repo or in these docs.
- Hover over terms like VIP or OSD for a short explanation, or see the
  [glossary](reference/glossary.md).
