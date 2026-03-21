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

## Route Advertisement

The switch advertises its management subnet to peers via the `bgp-networks` address list (configured in bgp.rsc). This gives peers a route back to the switch and the management network. The FRR peer receives this automatically — verify with:

```bash
sudo vtysh -c "show bgp ipv4 unicast"
```

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

## Internet Access

RouterOS cannot advertise a usable IPv4 default route via BGP with ENHE (see `docs/architecture.md`). Instead, configure the peer's network interface with a static default route via the switch's link-local address and public DNS.

### systemd-networkd Configuration

Create a networkd config that overrides the default netplan DHCP config. The filename must sort before the netplan-generated file in `/run/systemd/network/`.

```ini
# /etc/systemd/network/05-peering.network
[Match]
Name=enP3p49s0

[Network]
DHCP=no
LinkLocalAddressing=ipv6
DNS=1.1.1.1
DNS=1.0.0.1
Domains=~.

[Route]
Destination=0.0.0.0/0
Gateway=<switch-link-local>
GatewayOnLink=true

[IPv6AcceptRA]
UseGateway=false
UseDNS=false
```

Replace `<switch-link-local>` with the switch's link-local address on the peering VLAN (find it with `/ipv6 address print where interface=vlanNNN` on the switch).

Apply:

```bash
sudo systemctl restart systemd-networkd
```

### Switch-Side Requirements

The switch needs a masquerade NAT rule and a CPU-processed default route (see `docs/architecture.md` for details):

```
/ip firewall nat add chain=srcnat out-interface=vlan1 action=masquerade
/ip route add dst-address=0.0.0.0/0 gateway=192.168.178.1 distance=1 suppress-hw-offload=yes comment=internet-via-cpu
```

### Limitations

- **No Fritz!Box DNS:** the upstream router's subnet (`192.168.178.0/24`) is unreachable from peers because it matches a HW-offloaded connected route on the switch (no NAT). Use public DNS instead.
- **No global IPv6:** peers only have IPv6 link-local on the peering interface. IPv6 internet requires DHCPv6-PD from the upstream router — not yet implemented.
