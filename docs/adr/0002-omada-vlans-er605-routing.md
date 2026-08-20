# ADR-0002 — VLANs defined in Omada and routed by the ER605; no firewall VM

- **Status:** Accepted
- **Decided:** 2026-08-16, revised the same session when the real topology was known
- **Recorded:** 2026-08-20

## Context

The lab needs its own layer-2 segment: Kubernetes nodes, a corosync ring and
service VIPs have no business sharing a broadcast domain with a games console
and a TV streamer, and the corosync ring in particular is latency-sensitive
enough that household traffic is a real risk to cluster stability.

The first design put the lab behind an **OPNsense VM on `pve-lenovo`**, tagged
out through a managed switch, on the assumption that the house router was a
consumer box with no VLAN support.

That assumption was wrong. The house network is a TP-Link Omada stack — ER605
gateway, two ES205G/ES205GP switches, an OC200 controller and an EAP650 access
point, behind an Odido fibre ONT on WAN VLAN 300 — which is VLAN-capable end to
end and centrally managed. A TP-Link TL-SG105E ("Easy Smart", 802.1Q but not
Omada-adoptable) was already in hand for the lab leg.

Two constraints shaped the rest. The estate has 32 GB of RAM in total across two
nodes and is already close to fully allocated. And the household is live: the
person doing this work is not the only person using the network.

## Decision

Define every VLAN in the Omada controller and let the **ER605 route and firewall
between them**. No OPNsense VM, no firewall guest of any kind. The TL-SG105E
carries the lab leg as an 802.1Q access switch, trunked up from the ES205G.

Four VLANs: `99` mgmt, `30` trusted, `50` guest, `60` labnet
(`10.10.60.0/24`, lab hosts on statics).

Implement it in two phases. **Phase A** is labnet only — purely additive,
nothing existing moves. **Phase B** is the trusted/guest/mgmt VLANs, the SSIDs,
the inter-VLAN ACLs, and moving the Omada gear itself onto the management VLAN.

## Options considered

| Option                                       | Why it was plausible                                                                                            | Why it lost                                                                                                                                                                                                              |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| OPNsense VM as the lab router and firewall   | Far better firewalling than a consumer gateway: IDS/IPS, granular rules, real logging — and a skill worth showing | **Circular dependency:** the firewall for the lab network would run _on_ the hypervisor it firewalls, so every host reboot takes the network down with it, including the path used to fix it. Also costs ~1.5 GB of scarce RAM. |
| **VLANs in Omada, ER605 routes**             | The gear already does this; one control plane for the whole house; zero purchases; no RAM cost                    | **Chosen.** The freed RAM goes to the Talos control-plane VM.                                                                                                                                                            |
| Flat network, isolate inside Kubernetes only | Simplest possible; Cilium network policy covers pod-to-pod traffic anyway                                        | Does nothing for the corosync ring, the Proxmox management interfaces or the hypervisors themselves — all of which sit below Kubernetes and would stay exposed to household traffic.                                       |
| Build all four VLANs in one session          | One disruption instead of two; the design was already drawn                                                      | Moving the Omada gear onto a management VLAN is the highest lock-yourself-out step in the plan: done wrong, the controller loses the devices it manages, and the blast radius is the whole household's internet.            |

## Consequences

- **The ER605's ACL model is the ceiling for east-west policy.** No IDS/IPS, no
  L7 rules. Accepted: intra-cluster policy is Cilium's job
  ([ADR-0004](0004-cilium-at-bootstrap.md)), and the gateway only has to keep
  segments apart.
- **The TL-SG105E is managed by hand.** It is not Omada-adoptable, so it never
  appears in the controller's topology and its configuration lives in
  [`docs/network.md`](../network.md) instead. Treat that table as configuration,
  not prose — it is the only record of the switch's VLAN state.
- **One switch-level failure mode is worth knowing before it happens.** The
  SG105E's own UI warns that disabling 802.1Q restores every PVID to 1. If that
  ever happens, all three lab hosts land on the flat LAN while still holding
  `10.10.60.x` statics — every lab host unreachable at once, with nothing in any
  host log to explain it. Check that page first.
- **A port is reserved as an escape hatch.** SG105E port 5 stays untagged on the
  native VLAN, so it reaches the flat LAN even if VLAN 60 fails completely. This
  was gated during the build rather than assumed: ports 2–4 each returned a
  `10.10.60.x` lease and port 5 returned a flat-LAN lease, which is the proof
  that the hatch works.
- **Port budget is the binding hardware constraint.** The ES205G is full, and
  the SG105E is full at three lab hosts plus uplink plus escape hatch. A fourth
  lab host requires new switch hardware — which makes this ADR, not the roadmap,
  the place that explains why "just add a node" is not free.
- **Until phase B, labnet is reachable from the flat LAN by default inter-VLAN
  routing.** Deliberate — it is how the work laptop manages the lab — and it
  means the segmentation is currently organisational rather than enforced. The
  ACLs that make it real are phase B.
