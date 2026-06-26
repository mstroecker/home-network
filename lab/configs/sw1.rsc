# sw1.rsc — containerlab CHR config.
#
# Peering design (lab-specific, differs from production base.rsc):
#   The FRR + inter-switch ports are ROUTED L3 ports (not bridged), so each has
#   its own unique link-local. Production bridges every port and peers over
#   shared-link-local `vlanNNN` interfaces — but on CHR that wedges: multiple
#   unnumbered eBGP sessions sourced from one shared bridge link-local collide
#   and never converge when the FRR peers are dual-homed. Routed peering ports
#   (unique link-locals) avoid the collision and establish reliably.
#
#   The mgmt/uplink port (ether5) DOES keep the production `vlan1`-on-a-bridge
#   pattern (mgmt subnet + upstream DHCP).
#
# CHR deviations: ether1 = vrnetlab mgmt (untouched); no L3HW offload; no jumbo.
#
# Interface map: ether1 = mgmt, ether2 = frr1, ether3 = frr2,
#                ether4 = sw2 (inter-switch), ether5 = uplink (vlan1).

/system identity set name=sw1

# --- Mgmt/uplink: ether5 on a vlan1 bridge (mirrors base.rsc mgmt pattern) ---
/interface bridge add name=bridge vlan-filtering=no
/interface bridge port add bridge=bridge interface=ether5 pvid=1
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether5 vlan-ids=1
/interface vlan add interface=bridge name=vlan1 vlan-id=1
/interface bridge set bridge vlan-filtering=yes
/ip address add address=192.168.89.1/24 interface=vlan1
/ip dhcp-client add interface=vlan1 use-peer-dns=yes add-default-route=yes

# --- Routed peering ports: unnumbered eBGP discovers peers via IPv6 ND ---
# prefix=none makes the switch send Router Advertisements (RFC 4861) so peers
# auto-discover its (per-port, unique) link-local.
/ipv6 nd prefix add prefix=none interface=ether2
/ipv6 nd prefix add prefix=none interface=ether3
/ipv6 nd prefix add prefix=none interface=ether4
/ipv6 settings set accept-router-advertisements=yes

# --- BGP ---
# multipath=N (RouterOS 7.22+) installs up to N equal-cost BGP paths (ECMP).
/routing bgp instance add name=default as=65001 router-id=192.168.89.1 multipath=4
/routing bgp template add name=ebgp-default as=65001 afi=ip,ipv6 use-bfd=yes
/routing bfd configuration add disabled=no min-rx=1s min-tx=1s multiplier=3
# Advertised network: the mgmt subnet (connected route on vlan1)
/ip firewall address-list add list=bgp-networks address=192.168.89.0/24

# Peer: frr1 on ether2
/routing bgp connection add name=peer-frr1 instance=default templates=ebgp-default local.address=ether2 .role=ebgp output.network=bgp-networks
# Peer: frr2 on ether3
/routing bgp connection add name=peer-frr2 instance=default templates=ebgp-default local.address=ether3 .role=ebgp output.network=bgp-networks
# Peer: inter-switch link to sw2 on ether4
/routing bgp connection add name=peer-sw2 instance=default templates=ebgp-default local.address=ether4 .role=ebgp output.network=bgp-networks

# --- Internet for peers: masquerade out the uplink (mirrors upstream.rsc) ---
/ip firewall nat add chain=srcnat out-interface=vlan1 action=masquerade
