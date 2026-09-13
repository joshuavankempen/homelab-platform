#!/usr/bin/env python3
"""Read-only discovery of the Proxmox cluster through the API.

The OpenTofu VM layer needs facts that no file in this repository records:
storage IDs and free space, which datastore accepts `iso` content, whether
`vmbr0` is VLAN-aware, free memory per node, and the VM IDs already in use.

This script only reads. Every call is a GET, so it needs no `--dry-run` switch.

It doubles as the first test of the `TofuVM` role. A `403` names the endpoint
that the role cannot reach, which is far easier to read than the same failure
arriving in the middle of a `tofu plan`.

Credentials come from the environment, the same two variables the provider
reads:

    PROXMOX_VE_ENDPOINT    https://10.10.60.11:8006/
    PROXMOX_VE_API_TOKEN   tofu@pve!vm-layer=<uuid>

Usage:

    python scripts/discover_pve_api.py --insecure
    python scripts/discover_pve_api.py --insecure > ~/pve-api-discovery.txt
    python scripts/discover_pve_api.py --insecure --json > discovery.json

`--insecure` is required against a default Proxmox install, which serves a
self-signed certificate. The script fails closed without it: a silent fallback
to an unverified connection is the behaviour that makes TLS worthless.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
log = logging.getLogger("discover-pve-api")

# Endpoints that need a privilege the minimal role may lack. The message names
# the privilege, so a 403 tells you what to add rather than that something broke.
PRIVILEGE_HINTS = {
    "/cluster/status": "Sys.Audit",
    "/cluster/resources": "VM.Audit",
    "/cluster/nextid": "VM.Allocate",
    "/nodes": "Sys.Audit",
    "/storage": "Datastore.Audit",
}


class ApiError(RuntimeError):
    """A request failed in a way the caller should report, not retry."""


class ProxmoxApi:
    """A read-only Proxmox API client.

    It holds no mutating method on purpose. Adding one here would make this
    script a thing that can change the cluster, which it must never be.
    """

    def __init__(self, endpoint: str, token: str, verify_tls: bool) -> None:
        self.base = endpoint.rstrip("/") + "/api2/json"
        self.token = token
        if verify_tls:
            self.ssl_context = ssl.create_default_context()
        else:
            self.ssl_context = ssl._create_unverified_context()
            log.warning("TLS verification is OFF. The certificate is not checked.")

    def get(self, path: str, **params: str) -> Any:
        """GET one endpoint and return its `data` member."""
        url = f"{self.base}{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"

        request = urllib.request.Request(url, method="GET")
        request.add_header("Authorization", f"PVEAPIToken={self.token}")

        try:
            with urllib.request.urlopen(
                request, context=self.ssl_context, timeout=20
            ) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 401:
                raise ApiError(
                    f"401 on {path}. The token is wrong, expired, or removed. "
                    "Check PROXMOX_VE_API_TOKEN, and note the required shape: "
                    "user@realm!tokenid=uuid"
                ) from error
            if error.code == 403:
                hint = PRIVILEGE_HINTS.get(path.split("?")[0])
                detail = f" The role probably lacks {hint}." if hint else ""
                raise ApiError(f"403 on {path}.{detail}") from error
            raise ApiError(f"HTTP {error.code} on {path}: {error.reason}") from error
        except urllib.error.URLError as error:
            raise ApiError(
                f"cannot reach {url}: {error.reason}. "
                "A certificate error here means you need --insecure."
            ) from error

        return payload.get("data")

    def get_or_none(self, path: str, **params: str) -> Any:
        """GET an endpoint, and report a failure as a finding instead of an exit.

        One unreachable endpoint should not discard a whole report. A missing
        privilege is itself a result worth printing.
        """
        try:
            return self.get(path, **params)
        except ApiError as error:
            log.warning("%s", error)
            return None


def gib(value: Any) -> str:
    """Format a byte count as GiB. PVE reports bytes everywhere."""
    try:
        return f"{int(value) / 1024**3:,.1f} GiB"
    except (TypeError, ValueError):
        return "?"


def mib(value: Any) -> str:
    try:
        return f"{int(value) / 1024**2:,.0f} MiB"
    except (TypeError, ValueError):
        return "?"


def collect(api: ProxmoxApi) -> dict[str, Any]:
    """Gather every fact the VM layer needs, in one pass."""
    facts: dict[str, Any] = {}

    log.info("reading version and cluster status")
    facts["version"] = api.get_or_none("/version")
    facts["cluster_status"] = api.get_or_none("/cluster/status")

    log.info("reading guests and the next free VMID")
    facts["guests"] = api.get_or_none("/cluster/resources", type="vm")
    facts["nextid"] = api.get_or_none("/cluster/nextid")

    log.info("reading storage definitions")
    facts["storage_config"] = api.get_or_none("/storage")

    nodes = api.get_or_none("/nodes") or []
    facts["nodes"] = {}
    for node in nodes:
        name = node.get("node")
        if not name:
            continue
        log.info("reading node %s", name)
        facts["nodes"][name] = {
            "summary": node,
            "status": api.get_or_none(f"/nodes/{name}/status"),
            "storage": api.get_or_none(f"/nodes/{name}/storage"),
            "network": api.get_or_none(f"/nodes/{name}/network"),
        }

    return facts


def heading(title: str) -> None:
    print(f"\n{'=' * 70}\n== {title}\n{'=' * 70}")


def report_cluster(facts: dict[str, Any]) -> None:
    heading("CLUSTER")

    version = facts.get("version") or {}
    print(f"Proxmox VE : {version.get('version', '?')}")
    print(f"Release    : {version.get('release', '?')}")

    status = facts.get("cluster_status") or []
    cluster = next((i for i in status if i.get("type") == "cluster"), {})
    members = [i for i in status if i.get("type") == "node"]

    print(f"\nCluster    : {cluster.get('name', '?')}")
    print(f"Quorate    : {cluster.get('quorate', '?')}")
    print(f"Nodes      : {cluster.get('nodes', len(members))}")

    for member in members:
        online = "online" if member.get("online") else "OFFLINE"
        local = " (local)" if member.get("local") else ""
        print(
            f"  - {member.get('name'):<12} {online:<8}"
            f" nodeid={member.get('nodeid', '?')}"
            f" ip={member.get('ip', '?')}{local}"
        )

    # /cluster/status carries no vote count, so do not invent one. Membership and
    # the presence of a qdevice entry are what this endpoint can actually answer.
    # `pvecm status` on a node reports the votes.
    has_qdevice = any("qdevice" in str(i.get("type", "")).lower() for i in status)
    if has_qdevice:
        print("\n  QDevice: present.")
    elif len(members) == 2:
        print(
            "\n  ** Two nodes and NO QDevice member in /cluster/status."
            "\n     There is no third vote, so quorum has no margin. When either"
            "\n     node stops, the survivor drops below quorum and /etc/pve"
            "\n     turns read-only. A tofu apply then fails, at exactly the"
            "\n     moment you want to rebuild a node."
            "\n     Confirm the vote count with `pvecm status` on a node."
        )


def report_guests(facts: dict[str, Any]) -> None:
    heading("GUESTS AND VMIDs")

    guests = facts.get("guests") or []
    if not guests:
        print("No VMs or containers exist. Every VMID is free.")
    else:
        print(f"{'VMID':<8}{'NAME':<24}{'NODE':<14}{'TYPE':<8}{'STATUS':<10}MEM")
        for guest in sorted(guests, key=lambda g: int(g.get("vmid", 0))):
            print(
                f"{guest.get('vmid', '?'):<8}"
                f"{str(guest.get('name', '-'))[:22]:<24}"
                f"{guest.get('node', '?'):<14}"
                f"{guest.get('type', '?'):<8}"
                f"{guest.get('status', '?'):<10}"
                f"{gib(guest.get('maxmem'))}"
            )

    print(f"\nNext free VMID: {facts.get('nextid', '?')}")


def report_storage(facts: dict[str, Any]) -> None:
    heading("STORAGE")

    # The Talos ISO needs a datastore whose content list holds `iso`. The VM
    # disks need one that holds `images`. They are often different datastores.
    print("Per node, from /nodes/<node>/storage:\n")
    print(f"{'NODE':<14}{'STORAGE':<16}{'TYPE':<10}{'CONTENT':<28}{'AVAIL':>12}")

    iso_capable: set[str] = set()
    image_capable: set[str] = set()

    for name, node in (facts.get("nodes") or {}).items():
        for store in node.get("storage") or []:
            content = store.get("content", "")
            store_id = store.get("storage", "?")
            if "iso" in content:
                iso_capable.add(f"{name}:{store_id}")
            if "images" in content:
                image_capable.add(f"{name}:{store_id}")
            print(
                f"{name:<14}"
                f"{store_id:<16}"
                f"{store.get('type', '?'):<10}"
                f"{content[:26]:<28}"
                f"{gib(store.get('avail')):>12}"
            )

    print("\nAccepts `iso` (Talos boot media):")
    for item in sorted(iso_capable) or ["  none - the image resource has nowhere to go"]:
        print(f"  {item}")

    print("\nAccepts `images` (VM disks):")
    for item in sorted(image_capable) or ["  none - VMs cannot be created"]:
        print(f"  {item}")


def report_nodes(facts: dict[str, Any]) -> None:
    for name, node in (facts.get("nodes") or {}).items():
        heading(f"NODE - {name}")

        status = node.get("status") or {}
        memory = status.get("memory") or {}
        cpu_info = status.get("cpuinfo") or {}

        total = int(memory.get("total", 0) or 0)
        used = int(memory.get("used", 0) or 0)
        print(f"CPU sockets/cores : {cpu_info.get('sockets', '?')}/{cpu_info.get('cpus', '?')}")
        print(f"CPU model         : {cpu_info.get('model', '?')}")
        print(f"Memory total      : {gib(total)}")
        print(f"Memory used       : {gib(used)}")
        print(f"Memory free       : {gib(total - used)}")
        print(f"Uptime (s)        : {status.get('uptime', '?')}")

        # A VLAN tag on a VM NIC only takes effect when the bridge filters
        # VLANs. Without it the tag is ignored in silence, and the VM lands on
        # the untagged network. That reads as a network fault, not a config one.
        print("\nBridges:")
        interfaces = node.get("network")
        if interfaces is None:
            # An empty section used to look like "no bridges exist", which is a
            # different and much more alarming fact than "the query failed".
            print("  /nodes/<node>/network returned nothing. Read the stderr")
            print("  warnings: a 403 here means the role lacks Sys.Audit.")
            continue
        # Match OVSBridge too, and do not assume the key is spelled `bridge`.
        bridges = [i for i in interfaces if "bridge" in str(i.get("type", "")).lower()]
        if not bridges:
            kinds = sorted({str(i.get("type", "?")) for i in interfaces})
            print(f"  No bridge among {len(interfaces)} interfaces. Types: {kinds}")
            continue
        for iface in bridges:
            # `bridge_vlan_aware` is absent, not 0, when filtering is off.
            aware = str(iface.get("bridge_vlan_aware", "0")) == "1"
            verdict = "VLAN-AWARE" if aware else "NOT VLAN-aware"
            address = iface.get("cidr") or iface.get("address") or "-"
            print(
                f"  {iface.get('iface', '?'):<10}"
                f" {address:<20}"
                f" ports={str(iface.get('bridge_ports', '-')):<10}"
                f" {verdict}"
            )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read-only Proxmox discovery for the OpenTofu VM layer.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("PROXMOX_VE_ENDPOINT"),
        help="API base URL. Defaults to PROXMOX_VE_ENDPOINT.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("PROXMOX_VE_API_TOKEN"),
        help="API token, as user@realm!tokenid=uuid. Defaults to "
        "PROXMOX_VE_API_TOKEN. Prefer the variable: an argument is visible "
        "in the process list and in shell history.",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Skip TLS verification. Required against a self-signed Proxmox "
        "certificate. The script fails closed without it.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the raw facts as JSON instead of a report.",
    )
    return parser.parse_args(argv)


def preflight(args: argparse.Namespace) -> None:
    """Fail closed on missing configuration, before any request."""
    if not args.endpoint:
        raise SystemExit(
            "PROXMOX_VE_ENDPOINT is not set, and --endpoint was not given.\n"
            "  PowerShell: $env:PROXMOX_VE_ENDPOINT = 'https://10.10.60.11:8006/'"
        )
    if not args.token:
        raise SystemExit(
            "PROXMOX_VE_API_TOKEN is not set, and --token was not given.\n"
            "  PowerShell: $env:PROXMOX_VE_API_TOKEN = 'tofu@pve!vm-layer=<uuid>'"
        )
    if "!" not in args.token or "=" not in args.token:
        raise SystemExit(
            "the token does not look like user@realm!tokenid=uuid. "
            "Pass the whole string, not the UUID alone."
        )
    # A pasted placeholder passes the shape test above, and then costs one
    # three-second authentication delay per endpoint before it reports a 401
    # that names the wrong cause. Catch it here instead.
    if "<" in args.token or ">" in args.token:
        raise SystemExit(
            "the token still contains a placeholder in angle brackets. "
            "Substitute the real UUID from `pveum user token add`."
        )
    secret = args.token.split("=", 1)[1]
    if len(secret) < 30:
        raise SystemExit(
            f"the part after `=` is {len(secret)} characters. A Proxmox token "
            "UUID is 36. Check that the whole value was copied."
        )


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=sys.stderr)

    preflight(args)

    api = ProxmoxApi(args.endpoint, args.token, verify_tls=not args.insecure)

    try:
        facts = collect(api)
    except ApiError as error:
        log.error("%s", error)
        return 1

    if args.json:
        print(json.dumps(facts, indent=2, sort_keys=True))
        return 0

    print("Proxmox discovery report - read-only, through the API")
    print(f"Endpoint: {args.endpoint}")
    report_cluster(facts)
    report_guests(facts)
    report_storage(facts)
    report_nodes(facts)
    print()
    log.info("discovery complete")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
