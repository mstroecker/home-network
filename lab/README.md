# containerlab — home-network mirror

A virtual mirror of the production CRS310 / FRR topology for testing the
eBGP-unnumbered control plane without touching hardware. Each FRR node is
**dual-homed** — it peers with both switches.

```
      ┌──────── sw1 ══(eBGP inter-switch)══ sw2 ────────┐
      │  65001 ╱  │                          │  ╲ 65002 │
   (eBGP)    ╱  (eBGP)                    (eBGP) ╲    (eBGP)
      │    ╱      │                          │     ╲     │
     frr1 ────────┘                          └──────── frr2
    65010                                              65020
      │                                                 │
      └ uplink ───────── fritzbox ───────────── uplink ─┘
                       (DHCP + NAT = "internet")
```

Both FRR nodes peer with **both** switches, so each learns every prefix over two
paths — handy for exercising multipath/failover (drop a link and watch BFD
reconverge onto the other switch).

| Node     | Role                | ASN   | Notes                                  |
|----------|---------------------|-------|----------------------------------------|
| sw1      | MikroTik RouterOS   | 65001 | router-id 192.168.89.1                 |
| sw2      | MikroTik RouterOS   | 65002 | router-id 192.168.90.1                 |
| frr1     | FRR peer            | 65010 | announces 10.65.10.0/24                |
| frr2     | FRR peer            | 65020 | announces 10.65.20.0/24                |
| fritzbox | Alpine (DHCP + NAT) | —     | 192.168.178.1/24, masquerades to host  |

## What this is and isn't

containerlab runs MikroTik as **RouterOS CHR** — a software router with no switch
chip. The lab keeps the production `vlan1`-on-a-bridge management pattern (mgmt
subnet + upstream DHCP on `ether5`), but the **FRR + inter-switch peering ports
are routed L3 ports**, not bridged `vlanNNN` interfaces.

Why the deviation: production bridges every port and peers eBGP over
shared-link-local `vlanNNN` interfaces (all VLAN interfaces inherit the one
bridge MAC). On real hardware with single-homed peers that's fine. On **CHR with
dual-homed peers** it wedges — multiple unnumbered sessions sourced from the same
bridge link-local collide and never converge (one switch wins the race, the other
hangs). Routing the peering ports gives each a unique link-local, which
establishes reliably. See the header comments in `configs/sw*.rsc`.

Other hardware-specific bits are also dropped: **L3 hardware offloading**, **jumbo
MTU + MSS clamping**, `suppress-hw-offload`. And **ether1** is the vrnetlab mgmt
interface, left untouched.

## Prerequisites

1. **containerlab** + Docker installed.
2. **RouterOS CHR image** — built once via the helper in [`mikrotik-vm/`](mikrotik-vm/):
   ```bash
   cd mikrotik-vm && make build      # -> vrnetlab/mikrotik_routeros:7.22
   ```
   Builds 7.22 (matches the production hardware). Don't bump to 7.23.1+ — it
   hangs at the serial login under vrnetlab; see `mikrotik-vm/README.md`.
3. FRR + Alpine images are pulled automatically.

## Run

```bash
cd lab
sudo clab deploy -t home-network.clab.yml
# ... tear down with:
sudo clab destroy -t home-network.clab.yml --cleanup
```

## Web UI (WebFig / Winbox)

Each switch's RouterOS UI is published to the host (the vrnetlab container DNATs
all ports to RouterOS, so the published port maps straight through). Default
credentials: **`admin` / `admin`**.

| Switch | WebFig (HTTP)           | WebFig (HTTPS)           | Winbox            | Mgmt IP        |
|--------|-------------------------|--------------------------|-------------------|----------------|
| sw1    | http://localhost:8081   | https://localhost:8441   | localhost:8291    | 172.20.20.11   |
| sw2    | http://localhost:8082   | https://localhost:8442   | localhost:8292    | 172.20.20.12   |

On Linux the mgmt network is also directly routable, so `http://172.20.20.11`
works without the published ports. SSH: `ssh admin@172.20.20.11`.

## Interface mapping (vrnetlab quirk)

RouterOS `ether1` is the management port, so containerlab's data interfaces are
offset by one:

| containerlab | RouterOS | connects to        |
|--------------|----------|--------------------|
| `sw:eth1`    | `ether2` | frr1               |
| `sw:eth2`    | `ether3` | frr2               |
| `sw:eth3`    | `ether4` | other switch       |
| `sw:eth4`    | `ether5` | fritzbox uplink    |

On each FRR node: `eth1` → sw1, `eth2` → sw2.

The `.rsc` files configure `ether2..5`. Verify after boot with
`/interface ethernet print`.

## Verify

```bash
# Switch side (default creds admin / no password on a fresh CHR):
ssh admin@clab-home-network-sw1
  /routing bgp session print
  /routing bfd session print
  /ip route print where bgp
  /ip dhcp-client print              # should show a 192.168.178.x lease

# FRR side:
docker exec clab-home-network-frr1 vtysh -c "show bgp summary"
docker exec clab-home-network-frr1 vtysh -c "show bgp ipv4 unicast"
docker exec clab-home-network-frr1 vtysh -c "show ip route 10.65.20.0/24"  # expect 2 nexthops (ECMP)

# Switch ECMP (RouterOS 7.22 multipath=N on the instance): a peer prefix
# reachable both directly and via the other switch should install >1 nexthop.
ssh admin@clab-home-network-sw1 "/ip route print detail where dst-address=10.65.20.0/24"

# End-to-end: switch reaches the internet through the fritzbox NAT:
ssh admin@clab-home-network-sw1 "/ping 1.1.1.1 count=3"
```

Expected: each switch has **4 sessions** (frr1, frr2, the other switch — and the
FRR peers each appear once); each FRR node has **2 sessions** (one per switch)
and learns every remote prefix over both paths. frr1 learns `10.65.20.0/24` and
both switch management subnets; switches ping out via the fritzbox. Down a link
(`docker exec clab-home-network-frr1 ip link set eth1 down`) and the routes
should reconverge onto the other switch within the BFD detection time (~3s).

## Notes / not modeled

- **Peer internet** (frr1/frr2 → internet) needs the static default route via the
  switch's link-local described in `../docs/peer-frr.md`; the switch-side
  masquerade is already in the `.rsc`. The link-local is dynamic, so it's left as
  a manual step rather than baked in.
- **IPv6 global / DHCPv6-PD** is not modeled (matches production TODO).
