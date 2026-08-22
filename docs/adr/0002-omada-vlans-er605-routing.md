# ADR-0002 — VLANs defined in Omada and routed by the ER605; no firewall VM

- **Status:** Accepted
- **Decided:** 2026-08-16, revised the same session when the real topology was known
- **Recorded:** 2026-08-20

## Context

The lab needs its own layer-2 segment. Kubernetes nodes, a corosync ring and
service VIPs must not share a broadcast domain with a games console and a TV
streamer. The corosync ring is latency-sensitive, so household traffic is a real
risk to cluster stability.

The first design put the lab behind an **OPNsense VM on `pve-lenovo`**, tagged
out through a managed switch. That design assumed the house router was a consumer
box without VLAN support.

That assumption was wrong. The house network is a TP-Link Omada stack: an ER605
gateway, two ES205G/ES205GP switches, an OC200 controller, and an EAP650 access
point. The stack sits behind an Odido fibre ONT on WAN VLAN 300. The stack is
VLAN-capable end to end, and one controller manages all of it. A TP-Link
TL-SG105E was already in hand for the lab leg. It is an "Easy Smart" model:
802.1Q capable, but Omada cannot adopt it.

Two constraints shaped the rest. The estate has 32 GB of RAM in total across two
nodes, and it is already close to fully allocated. The household network is live,
and other people use it.

## Decision

Define every VLAN in the Omada controller. Let the **ER605 route and filter
between them**. Use no OPNsense VM and no firewall guest of any kind. The
TL-SG105E carries the lab leg as an 802.1Q access switch, with a trunk up from
the ES205G.

Four VLANs: `99` mgmt, `30` trusted, `50` guest, `60` labnet
(`10.10.60.0/24`, lab hosts on statics).

Implement it in two phases. **Phase A** is labnet only. It is purely additive,
and nothing existing moves. **Phase B** is the trusted, guest and mgmt VLANs,
the SSIDs, and the inter-VLAN ACLs. It also moves the Omada gear itself onto the
management VLAN.

## Options considered

| Option                                       | Why it was plausible                                                                                            | Why it lost                                                                                                                                                                                                              |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| OPNsense VM as the lab router and firewall   | Far better traffic filtering than a consumer gateway: IDS/IPS, granular rules, real logs — and a skill worth a demonstration | **Circular dependency:** the firewall for the lab network would run _on_ the hypervisor it protects, so every host reboot takes the network down with it, including the path that repairs it. It also costs ~1.5 GB of scarce RAM. |
| **VLANs in Omada, ER605 routes**             | The gear already does this; one control plane for the whole house; zero purchases; no RAM cost                    | **Chosen.** The freed RAM goes to the Talos control-plane VM.                                                                                                                                                            |
| Flat network, isolate inside Kubernetes only | Simplest possible; Cilium network policy covers pod-to-pod traffic anyway                                        | It protects neither the corosync ring, nor the Proxmox management interfaces, nor the hypervisors. All three sit below Kubernetes, and all three would stay exposed to household traffic.                                |
| Build all four VLANs in one session          | One disruption instead of two; the design was already drawn                                                      | The move of the Omada gear onto a management VLAN is the step with the highest lock-out risk: done wrong, the controller loses the devices it manages, and the blast radius is the whole household's internet.            |

## Consequences

- **The ER605's ACL model is the ceiling for east-west policy.** It offers no
  IDS/IPS and no L7 rules. The project accepts that limit: Cilium owns
  intra-cluster policy ([ADR-0004](0004-cilium-at-bootstrap.md)), and the gateway
  only has to keep the segments apart.
- **An operator manages the TL-SG105E by hand.** Omada cannot adopt it, so it
  never appears in the controller's topology, and its configuration lives in
  [`docs/network.md`](../network.md) instead. Treat that table as configuration,
  not prose — it is the only record of the switch's VLAN state.
- **Learn one switch-level failure mode before it happens.** The SG105E's own UI
  warns that a disabled 802.1Q restores every PVID to 1. If that ever happens,
  all three lab hosts land on the flat LAN. Each still holds a `10.10.60.x`
  static address, so every lab host goes unreachable at once. No host log
  explains it. Check that page first.
- **One port is reserved as an escape hatch.** SG105E port 5 stays untagged on
  the native VLAN, so it reaches the flat LAN even if VLAN 60 fails completely.
  The build gated this rather than assumed it. Ports 2–4 each returned a
  `10.10.60.x` lease, and port 5 returned a flat-LAN lease. That is the proof
  that the hatch works.
- **The port budget is the binding hardware constraint.** The ES205G is full, and
  the SG105E is full at three lab hosts plus uplink plus escape hatch. A fourth
  lab host requires new switch hardware. That need makes this ADR, not the
  roadmap, the place that explains why an extra node is not free.
- **Until phase B, default inter-VLAN routing keeps labnet reachable from the
  flat LAN.** That is deliberate, because the work laptop manages the lab over
  that path, and it means the segmentation is currently organisational rather
  than enforced. Phase B adds the ACLs that enforce it.
