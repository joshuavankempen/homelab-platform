# ADR-0004 — Cilium as the CNI, installed at cluster bootstrap

- **Status:** Accepted
- **Decided:** 2026-08-16
- **Recorded:** 2026-08-20

## Context

Talos ships without a CNI, so the choice is made at bootstrap. It is also close
to irreversible in practice: swapping the CNI on a running cluster rebuilds every
pod's networking, and on a two-node cluster there is nowhere to drain to while
that happens.

Three things this cluster needs from its network layer beyond pod-to-pod traffic.
**Network policy**, because VLAN segmentation stops at the node boundary
([ADR-0002](0002-omada-vlans-er605-routing.md)) and everything inside the cluster
shares one flat pod network. **Stable service addresses on the lab VLAN**,
because the first planned workload is a DNS server, and a DNS server that changes
address when a pod reschedules is worse than no DNS server. And **observability
early**, since the monitoring stack is several sessions away and the network is
what will be misconfigured before then.

## Decision

**Cilium**, installed at bootstrap, with `kube-proxy` replacement enabled and
Hubble on. Service VIPs on the lab VLAN come from Cilium LB-IPAM plus L2
announcements. Flannel stays parked as the fallback.

## Options considered

| Option                          | Why it was plausible                                                                        | Why it lost                                                                                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Cilium, kube-proxy replaced** | eBPF dataplane, real network policy, LB-IPAM + L2 announcements, Hubble for flow visibility  | **Chosen.** The only option that answers all three requirements without adding a second component.                                                                 |
| Flannel                         | Simplest CNI there is; almost nothing to misconfigure; adequate for a two-node lab            | No network policy at all and no load-balancer story — service VIPs would need MetalLB alongside it, so "simpler" stops being true at the second requirement.        |
| Calico                          | Mature policy engine, very widely deployed, strong documentation                              | Policy yes, but no equivalent of LB-IPAM and no eBPF observability comparable to Hubble. Would still need MetalLB.                                                  |

## Consequences

- **A Cilium misconfiguration is a whole-cluster network outage.** That is the
  cost of one component owning dataplane, policy and load balancing together.
  Mitigated by installing it at bootstrap, when there is nothing running to
  break, and by changing it through Git afterwards.
- **`kube-proxy` replacement requires Talos-specific configuration.** The machine
  config must disable the built-in proxy and expose KubePrism as the API-server
  endpoint. Non-obvious the first time, and a broken cluster if half-done.
- **Service VIPs on labnet need no router change.** L2 announcements answer ARP
  for VIPs out of a reserved pool, so a load-balanced service gets a lab-VLAN
  address without touching the ER605. **The labnet DHCP scope must exclude that
  pool** — otherwise the router eventually leases an address Cilium is already
  claiming, and the failure presents as intermittent DNS rather than as an
  address conflict.
- **Observability arrives before the monitoring stack.** Hubble gives flow
  visibility from bootstrap, which is the difference between debugging the first
  GitOps deployments and guessing at them.
- **More to learn than Flannel would have needed.** Accepted: eBPF networking and
  Kubernetes network policy are the marketable half of this choice, not
  incidental complexity.
