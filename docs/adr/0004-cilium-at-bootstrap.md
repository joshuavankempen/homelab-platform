# ADR-0004 — Cilium as the CNI, installed at cluster bootstrap

- **Status:** Accepted
- **Decided:** 2026-08-16
- **Recorded:** 2026-08-20

## Context

Talos ships without a CNI, so the bootstrap step makes the choice. The choice is
also close to irreversible in practice. A CNI swap on a running cluster rebuilds
the network of every pod, and a two-node cluster has nowhere to drain to during
that rebuild.

This cluster needs three things from its network layer beyond pod-to-pod traffic.
**Network policy**, because VLAN segmentation stops at the node boundary
([ADR-0002](0002-omada-vlans-er605-routing.md)) and everything inside the cluster
shares one flat pod network. **Stable service addresses on the lab VLAN**: the
first planned workload is a DNS server. A DNS server that changes address on a
pod reschedule is worse than no DNS server. And **observability early**, because
the monitoring stack is several sessions away, and the network is the part most
likely to hold a misconfiguration before then.

## Decision

**Cilium**, installed at bootstrap, with `kube-proxy` replacement enabled and
Hubble on. Cilium LB-IPAM plus L2 announcements supply the service VIPs on the
lab VLAN. Flannel stays parked as the fallback.

## Options considered

| Option                          | Why it was plausible                                                                        | Why it lost                                                                                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Cilium, kube-proxy replaced** | eBPF dataplane, real network policy, LB-IPAM + L2 announcements, Hubble for flow visibility  | **Chosen.** It is the only option that answers all three requirements with one component.                                                                          |
| Flannel                         | Simplest CNI there is; almost nothing to misconfigure; adequate for a two-node lab            | It has no network policy and no load-balancer path. Service VIPs would need MetalLB beside it, so "simpler" stops being true at the second requirement.             |
| Calico                          | Mature policy engine, very widely deployed, strong documentation                              | It has policy, but no equivalent of LB-IPAM and no eBPF observability to match Hubble. It would still need MetalLB.                                                 |

## Consequences

- **A Cilium misconfiguration is a whole-cluster network outage.** One component
  owns the dataplane, the policy and the load balancing together, and that is the
  cost. The bootstrap install limits the risk, because no workload runs yet, and
  every later change goes through Git.
- **`kube-proxy` replacement requires Talos-specific configuration.** The machine
  config must disable the built-in proxy and expose KubePrism as the API-server
  endpoint. The step is non-obvious the first time, and a half-done step breaks
  the cluster.
- **Service VIPs on labnet need no router change.** L2 announcements answer ARP
  for the VIPs out of a reserved pool. A load-balanced service then gets a
  lab-VLAN address without a change to the ER605. **The labnet DHCP scope must
  exclude that pool.** Otherwise, the router eventually leases an address that
  Cilium already claims. The failure then presents as intermittent DNS rather
  than as an address conflict.
- **Observability arrives before the monitoring stack.** Hubble gives flow
  visibility from bootstrap, which is the difference between a real debug of the
  first GitOps deployments and a guess at them.
- **This choice needs more learning than Flannel would.** The project accepts
  that: eBPF networking and Kubernetes network policy are the marketable half of
  this choice, not incidental complexity.
