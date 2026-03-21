# Home Network Architecture

## Switches

Two identical MikroTik CRS310-8G+2S+ switches (Marvell 98DX226S / DX3230L switch chip, RouterOS 7.22 stable) acting as eBGP routers with IPv6 link-local peering.

| | sw1 | sw2 |
|--|-----|-----|
| Management IP | 192.168.89.1/24 | 192.168.90.1/24 |
| ASN | 65001 | 65002 |
| Router ID | 192.168.89.1 | 192.168.90.1 |
| Inter-switch port | sfp-sfpplus1 (vlan107) | sfp-sfpplus1 (vlan107) |

## Port Layout

Both switches share the same port-to-VLAN mapping:

| Port | VLAN | MTU | Purpose |
|------|------|-----|---------|
| ether1 | 101 | 9000 | eBGP peer (isolated) |
| ether2 | 102 | 9000 | eBGP peer (isolated) |
| ether3 | 103 | 9000 | eBGP peer (isolated) |
| ether4 | 104 | 9000 | eBGP peer (isolated) |
| ether5 | 105 | 9000 | eBGP peer (isolated) |
| ether6 | 106 | 9000 | eBGP peer (isolated) |
| ether7 | 1 | 1500 | Management / general |
| ether8 | 1 | 1500 | Management / general |
| sfp-sfpplus1 | 107 | 9000 | eBGP peer (inter-switch link) |
| sfp-sfpplus2 | 108 | 9000 | eBGP peer (isolated) |

## Architecture Decisions

### Port Isolation via Bridge VLAN Filtering

Each eBGP-facing port (ether1-6, sfp-sfpplus1-2) is assigned a unique PVID and placed in its own VLAN. This is the only method on CRS3xx that provides L2 port isolation with hardware offloading. Without unique VLANs, traffic between bridge ports would be forwarded in hardware, bypassing the CPU entirely and making per-port routing/BGP impossible.

Each VLAN has a corresponding VLAN interface on the bridge (vlan101-108) which acts as the L3 interface for that port. IPv6 link-local addresses are auto-assigned on these interfaces, used for eBGP peering.

Ether7 and ether8 share VLAN 1 and remain bridged together for management access. A dedicated `vlan1` interface on the bridge carries the management IP.

**Critical: management IP must be on a VLAN interface, not the bridge directly.** When `vlan-filtering=yes` is set on the bridge, RouterOS applies it at boot before the VLAN table entries are loaded. If the management IP is on the bridge interface, traffic is dropped during this window and the switch becomes unreachable after every reboot. Placing the IP on a `vlan1` interface avoids this because the VLAN interface only comes up after the VLAN table is populated.

### Jumbo Frames (MTU 9000)

All eBGP-facing ports and their VLAN interfaces are configured with MTU 9000. The CRS310 supports up to 8 MTU profiles in hardware, so mixed MTU (9000 on peering ports, 1500 on management) works with full offloading.

**L2MTU is set to 10218 on all ports**, including ether7/8. This is required because the bridge derives its L2MTU from the minimum across all slave ports. If any port has a low L2MTU, it caps the VLAN interfaces. Raising L2MTU does not change the actual MTU of a port -- it only sets the maximum frame size the port can handle.

Important: changing L2MTU causes a switch chip reset and a brief connectivity drop. Disable L3 HW offloading before making MTU changes, then re-enable it.

### L3 Hardware Offloading

Two settings must both be enabled:

1. **Switch level:** `/interface ethernet switch set 0 l3-hw-offloading=yes`
2. **IPv6 specifically:** `/interface ethernet switch l3hw-settings set ipv6-hw=yes`

The first enables L3HW on the switch chip. The second enables IPv6 route offloading. Without both, the switch processes all L3 traffic in CPU (software).

### Path MTU Discovery and MSS Clamping

With mixed MTU (9000 on peering ports, 1500 toward the internet), servers sending jumbo frames to external destinations rely on Path MTU Discovery (PMTUD). The switch sends ICMPv6 Packet Too Big / ICMPv4 Fragmentation Needed messages when a packet exceeds the outgoing interface MTU. The sending server caches the discovered path MTU per destination (expires after ~10 minutes on Linux).

As a safety net for TCP, MSS clamping rules rewrite the TCP MSS in SYN packets to match the path MTU. This prevents oversized segments even when PMTUD fails (e.g., ICMP blocked upstream). For 9000-to-9000 connections, clamping is a no-op -- jumbo frames flow normally.

### DX3000-series MAC Address Limitation

When using L3HW with multiple MTU profiles, the DX3000 chip only allows the last octet of the MAC address to differ between interfaces. This is a hardware constraint and only applies to L3HW -- L2 bridging is unaffected.

## eBGP Design

### BGP Instance and Template

Each switch runs a single BGP instance with a device-specific AS and router-id. A shared template (`ebgp-default`) sets the address families to IPv4+IPv6 (`afi=ip,ipv6`). IPv4 routes are carried over the IPv6 link-local session using Extended Next Hop encoding (ENHE).

RouterOS 7 BGP hierarchy:
- **Instance** -- holds `router-id` and `as`, used for route selection
- **Template** -- holds `afi`, `as`, `use-bfd`, inherited by connections
- **Connection** -- per-peer config: `instance`, `templates`, `local.role`, `local.address`

Key syntax notes for RouterOS 7.22:
- Templates use `afi=ip,ipv6`, NOT `address-families`
- `router-id` belongs on the instance, NOT the template
- Connections require `instance=` parameter and `templates=` (plural)
- **Unnumbered mode:** set `local.address` to an interface name, leave `remote.address` empty. Requires `/ipv6 nd prefix add prefix=none interface=<vlan>` on the interface so RAs are sent for peer discovery (RFC 4861). Only one connection per interface.
- **Explicit mode:** set `local.address` to a link-local with zone ID (`fe80::xxxx%vlanNNN`). Connection creation works best in two steps: `add` with minimal params, then `set` the local.address

### BFD (Bidirectional Forwarding Detection)

BFD is **enabled** on the BGP template (`use-bfd=yes`) with 1s timers and multiplier 3 (3s detection time). Both sides must have BFD enabled — on RouterOS via the template, and on FRR via `neighbor <iface> bfd` in the BGP config.

### Route Advertisement

RouterOS 7 uses firewall address lists instead of BGP network statements. The management subnet is added to a `bgp-networks` address list, and each peer connection references it via `output.network=bgp-networks`. This ensures peers receive a route back to the switch's management network.

`output.network` is the only mechanism that correctly uses ENHE (IPv6 next-hop) for IPv4 prefixes. Routes advertised this way are resolved by the peer using the BGP session's link-local next-hop. See "RouterOS ENHE Bug" below for limitations of other mechanisms.

### Internet Access for Peers

RouterOS cannot advertise a usable IPv4 default route to peers via BGP due to ENHE limitations.

#### RouterOS ENHE Bug: IPv4 next-hop leaks on redistributed routes

When RouterOS redistributes a route that has an explicit IPv4 gateway (static, DHCP), it sends the original IPv4 gateway as the BGP next-hop instead of using ENHE (the local IPv6 link-local). Connected routes are unaffected — they have no IPv4 gateway to leak, so ENHE works correctly. Neither `nexthop-choice=force-self` nor output routing filters can override this behavior.

How this affects each advertisement mechanism:

- **`output.network`** (address list) — works correctly with ENHE for all prefixes. However, `0.0.0.0/0` in the address list is treated as a wildcard (match all), not as the default prefix, so the default route cannot be advertised this way.
- **`output.redistribute`** — connected routes use ENHE correctly. Static/DHCP routes leak their IPv4 gateway as the next-hop. The default route (`0.0.0.0/0`) is never redistributed at all regardless of route type.
- **`output.default-originate`** — sends `0.0.0.0/0` with the switch's IPv4 gateway (e.g. `192.168.178.1`) instead of ENHE. Output filter chains do not apply to default-originate routes.

**Workaround:** peers configure a static default route via the switch's link-local address in systemd-networkd (see `peers/frr.md`). This requires two additional pieces on the switch:

1. **Masquerade NAT** on vlan1 — the upstream router (Fritz!Box) does not know how to route peer prefixes (e.g. `10.65.10.0/24`) back. The switch masquerades outbound traffic so the Fritz!Box sees it from the switch's own DHCP address.

2. **Static default route with `suppress-hw-offload`** — L3 HW offloading forwards packets entirely in the switch chip, bypassing the CPU where NAT rules are processed. A duplicate static default route with `suppress-hw-offload=yes` forces internet-bound traffic through the CPU. This only affects traffic matching the default route; peer-to-peer traffic uses more specific BGP routes and remains hardware-offloaded.

```
/ip firewall nat add chain=srcnat out-interface=vlan1 action=masquerade
/ip route add dst-address=0.0.0.0/0 gateway=192.168.178.1 distance=1 suppress-hw-offload=yes comment=internet-via-cpu
```

**Limitation:** the upstream router's subnet (e.g. `192.168.178.0/24`) is unreachable from peers because it matches a connected route on the switch (HW-offloaded, no NAT). Peers must use public DNS (e.g. Cloudflare `1.1.1.1`) instead of the Fritz!Box DNS.

IPv6 internet for peers requires DHCPv6-PD to delegate global prefixes to the peering VLANs — not yet implemented.

### IPv6 Upstream

RouterOS defaults to `accept-router-advertisements=yes-if-forwarding-disabled`. Since the switches have `forward=yes` (required for routing), they ignore RAs from the upstream router and do not obtain a global IPv6 address via SLAAC. To fix this:

```
/ipv6 settings set accept-router-advertisements=yes
```

This is set manually (not in base.rsc) and allows the switch to get a global IPv6 address and default route from the upstream router (Fritz!Box) on vlan1. Full IPv6 internet for peers requires DHCPv6-PD to delegate prefixes to the peering VLANs — not yet implemented.

### Peer Connections

All 8 ports have disabled eBGP connections pre-configured with the local link-local address bound to their VLAN interface and `output.network=bgp-networks` for route advertisement. To activate a peer:

```
/routing bgp connection set peer-ether1 remote.address=<remote-ll>%vlan101 remote.as=<peer-asn>
/routing bgp connection enable peer-ether1
```

## Deployment

### Prerequisites

1. Fresh CRS310 with factory default config
2. SSH key bootstrapped: `./init-switch.sh <switch-ip>`

### One-Shot Deploy

```bash
./deploy.sh devices/sw2.env
```

The deploy script runs two phases:

1. **Phase 1 (base.rsc):** Bridge, VLANs, port isolation, MTU, ND prefixes, management IP, DHCP client, MSS clamping, L3HW offloading
2. **Phase 2 (bgp.rsc):** BGP instance, template, BFD config, 8 disabled unnumbered peer connections

### Activating the Inter-Switch Link

After both switches are deployed, activate the sfp-sfpplus1 / vlan107 peering:

On sw1:
```
/routing bgp connection set peer-sfp1 remote.address=<sw2-ll>%vlan107 remote.as=65002
/routing bgp connection enable peer-sfp1
```

On sw2:
```
/routing bgp connection set peer-sfp1 remote.address=<sw1-ll>%vlan107 remote.as=65001
/routing bgp connection enable peer-sfp1
```

### Verification

```
/routing bgp instance print detail
/routing bgp template print
/routing bgp connection print
/routing bgp session print
/routing bfd session print
```

## Operational Notes

- **VLAN filtering order matters.** Always configure PVIDs and VLAN table entries before enabling `vlan-filtering=yes` on the bridge. Enabling it first drops all traffic that doesn't match the (empty) VLAN table, locking you out.
- **Management access** depends on VLAN 1 including ether7/ether8 in the bridge VLAN table. If VLAN 1 is removed or misconfigured, management access is lost.
- **DHCP client** is configured on `vlan1` (not the bridge directly) and receives an upstream IP from the upstream router. This provides internet access and DNS to the switch.
- **IPv6 ND** is enabled with DNS advertisement (`advertise-dns=yes`).

## Project Structure

```
home-network/
├── architecture.md              # This file -- shared design documentation
├── devices/
│   ├── sw1.env                  # Switch: DEVICE_NAME, MGMT_IP, AS, ROUTER_ID
│   ├── sw2.env
│   └── orangepi5-plus.env       # FRR peer: AS, PEER_INTERFACE, ANNOUNCED_PREFIX
├── templates/
│   ├── base.rsc                 # Switch L2/L3 config (envsubst)
│   ├── bgp.rsc                  # Switch BGP config (envsubst)
│   └── frr.conf                 # FRR peer config (envsubst)
├── peers/
│   └── frr.md                   # Guide: connecting FRR peers to the switches
├── deploy.sh                    # One-shot switch deployment script
└── init-switch.sh               # SSH key bootstrap (takes IP as $1)
```
