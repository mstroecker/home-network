# No firewall rules on switches

**Priority:** Low

## Problem

The switches have no firewall filter rules — only MSS clamping (mangle) and masquerade NAT. Any device on a peering port gets full L3 access to:

- All other peers' announced prefixes (peer-to-peer via BGP routes)
- The management network (192.168.89.0/24, 192.168.90.0/24)
- The switch's own management interface (SSH, API, etc.)
- The upstream network (via NAT)

## Relevance

For a trusted home lab where all peers are your own machines, this is fine. Becomes a concern if:

- Any port faces a device you don't fully control
- A compromised peer could pivot to the management network or other peers
- You want to limit which peers can reach the internet

## If needed later

Typical rules would:

- Allow BGP (TCP/179) and BFD (UDP/3784-3785) on peering interfaces
- Allow ICMP/ICMPv6 (for PMTUD and diagnostics)
- Drop other traffic to the switch itself (`chain=input`)
- Optionally restrict peer-to-peer forwarding (`chain=forward`)

Not urgent — just noting the gap for awareness.
