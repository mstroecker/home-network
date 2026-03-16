# MikroTik CRS310-8G+2S+ Configuration

## Device

- **Model:** CRS310-8G+2S+ (Marvell 98DX226S / DX3230L switch chip)
- **Management IP:** 192.168.89.1/24 on vlan1 interface
- **RouterOS:** 7.22 (stable)
- **SSH:** Key-based authentication, user `admin`

## Port Layout

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
| sfp-sfpplus1 | 107 | 9000 | eBGP peer (isolated) |
| sfp-sfpplus2 | 108 | 9000 | eBGP peer (isolated) |

## Architecture

### Port Isolation via Bridge VLAN Filtering

Each eBGP-facing port (ether1-6, sfp-sfpplus1-2) is assigned a unique PVID and placed in its own VLAN. This is the only method on CRS3xx that provides L2 port isolation with hardware offloading. Without unique VLANs, traffic between bridge ports would be forwarded in hardware, bypassing the CPU entirely and making per-port routing/BGP impossible.

Each VLAN has a corresponding VLAN interface on the bridge (vlan101-108) which acts as the L3 interface for that port. IPv6 link-local addresses are auto-assigned on these interfaces, used for eBGP peering.

Ether7 and ether8 share VLAN 1 and remain bridged together for management access. A dedicated `vlan1` interface on the bridge carries the management IP (192.168.89.1).

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

As a safety net for TCP, MSS clamping rules rewrite the TCP MSS in SYN packets to match the path MTU. This prevents oversized segments even when PMTUD fails (e.g., ICMP blocked upstream). For 9000-to-9000 connections, clamping is a no-op — jumbo frames flow normally.

### DX3000-series MAC Address Limitation

When using L3HW with multiple MTU profiles, the DX3000 chip only allows the last octet of the MAC address to differ between interfaces. This is a hardware constraint and only applies to L3HW -- L2 bridging is unaffected.

## eBGP Configuration

### BGP Instance and Template

```
/routing bgp instance
add name=default as=65001 router-id=192.168.89.1

/routing bgp template
add name=ebgp-default as=65001 afi=ipv6 use-bfd=yes
```

The instance defines the router-id and AS for route selection. The template sets the address family to IPv6 and is inherited by all peer connections.

### Peer Connections

All 8 ports have disabled eBGP connections pre-configured with the local link-local address bound to their VLAN interface:

| Connection | Interface | Local Address |
|------------|-----------|---------------|
| peer-ether1 | vlan101 | fe80::d601:c3ff:febd:3c45%vlan101 |
| peer-ether2 | vlan102 | fe80::d601:c3ff:febd:3c45%vlan102 |
| peer-ether3 | vlan103 | fe80::d601:c3ff:febd:3c45%vlan103 |
| peer-ether4 | vlan104 | fe80::d601:c3ff:febd:3c45%vlan104 |
| peer-ether5 | vlan105 | fe80::d601:c3ff:febd:3c45%vlan105 |
| peer-ether6 | vlan106 | fe80::d601:c3ff:febd:3c45%vlan106 |
| peer-sfp1 | vlan107 | fe80::d601:c3ff:febd:3c45%vlan107 |
| peer-sfp2 | vlan108 | fe80::d601:c3ff:febd:3c45%vlan108 |

To activate a peer, set the remote address and AS, then enable:

```
/routing bgp connection set peer-ether1 remote.address=<remote-ll>%vlan101 remote.as=<peer-asn>
/routing bgp connection enable peer-ether1
```

### Verification

```
/routing bgp instance print detail
/routing bgp template print
/routing bgp connection print
/routing bgp session print
```

## Operational Notes

- **VLAN filtering order matters.** Always configure PVIDs and VLAN table entries before enabling `vlan-filtering=yes` on the bridge. Enabling it first drops all traffic that doesn't match the (empty) VLAN table, locking you out.
- **Management access** depends on VLAN 1 including ether7/ether8 in the bridge VLAN table. If VLAN 1 is removed or misconfigured, management access is lost.
- **DHCP client** is configured on `vlan1` (not the bridge directly) and receives an upstream IP (192.168.178.x range) from the Fritzbox on ether8. This provides internet access and DNS to the switch.
- **IPv6 ND** is enabled with DNS advertisement (`advertise-dns=yes`).
