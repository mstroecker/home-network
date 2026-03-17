# Peering with FRR

How to connect a Linux server running FRR to a CRS310 switch port.

## Prerequisites

- FRR installed with `bgpd` enabled in `/etc/frr/daemons`
- Server connected to an eBGP peering port (ether1-6, sfp-sfpplus1-2)

## Switch Side — Unnumbered BGP

Each peering VLAN interface needs an IPv6 ND prefix so the switch sends Router Advertisements (required for unnumbered peer discovery):

```
/ipv6 nd prefix add prefix=none interface=vlan101
```

Then add an unnumbered BGP connection — `local.address` is the interface name, no `remote.address`:

```
/routing bgp connection add instance=default local.address=vlan101 .role=ebgp name=peer-ether1 templates=ebgp-default
```

The switch auto-discovers the peer's link-local via IPv6 Neighbor Discovery (RFC 4861) and uses RFC 5549 for IPv4 NLRI with IPv6 next-hops.

## FRR Configuration

Unnumbered peering uses the interface name as the neighbor identifier:

```
# /etc/frr/frr.conf
frr defaults traditional
hostname myserver
log syslog informational
service integrated-vtysh-config
!
router bgp 65010
 no bgp ebgp-requires-policy
 neighbor enP3p49s0 interface remote-as 65001
 neighbor enP3p49s0 bfd
 !
 address-family ipv4 unicast
  neighbor enP3p49s0 activate
  network 10.65.10.0/24
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor enP3p49s0 activate
 exit-address-family
!
```

Key points:
- **`neighbor <iface> interface remote-as <asn>`** — single line, interface name IS the neighbor name
- ENHE is implicit in unnumbered mode (no `capability extended-nexthop` needed)
- **`no bgp ebgp-requires-policy`** disables FRR's default eBGP policy requirement

Apply:

```bash
sudo systemctl restart frr
```

## Announcing IPv4 Routes

The prefix must exist in the kernel routing table. Create a dummy interface:

```bash
sudo ip link add dummy0 type dummy
sudo ip link set dummy0 up
sudo ip addr add 10.65.10.1/24 dev dummy0
```

Then add `network 10.65.10.0/24` under `address-family ipv4 unicast` in the FRR config.

The switch receives the route with an IPv6 link-local next-hop via ENHE and installs it as a hardware-offloaded BGP route.

## Verification

On the server:

```bash
sudo vtysh -c "show bgp summary"
sudo vtysh -c "show bgp ipv4 unicast"
sudo vtysh -c "show bgp neighbor <interface>"
```

On the switch:

```
/routing bgp session print
/ip route print where bgp
```

## BFD

BFD is enabled on the BGP template (`use-bfd=yes`). The FRR config must also enable BFD:

```
neighbor <interface> bfd
```

Both sides must have BFD enabled for sessions to establish. Without `neighbor <iface> bfd` on the FRR side, the switch sends BFD packets but never receives replies, and BGP flaps.
