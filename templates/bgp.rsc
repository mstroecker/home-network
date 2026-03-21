# bgp.rsc — BGP configuration for CRS310-8G+2S+
# Variables: AS, ROUTER_ID, MGMT_IP

# --- BGP instance ---
/routing bgp instance add name=default as=${AS} router-id=${ROUTER_ID}

# --- BGP template ---
# afi=ip,ipv6: IPv4 routes via Extended Next Hop (ENHE), IPv6 native
/routing bgp template add name=ebgp-default as=${AS} afi=ip,ipv6 use-bfd=yes

# --- BFD ---
/routing bfd configuration add disabled=no min-rx=1s min-tx=1s multiplier=3

# --- BGP network advertisement ---
# RouterOS 7 uses firewall address lists for BGP network statements.
# Peers receive these prefixes so they can route traffic back to the switch.
/ip firewall address-list add list=bgp-networks address=${MGMT_IP}

# --- Peer connections (unnumbered, all disabled) ---
# local.address is the VLAN interface name — the switch auto-discovers
# the peer's link-local via IPv6 ND (requires ND prefix on the interface, see base.rsc).
# To activate: set remote.address and remote.as, then enable.
/routing bgp connection add name=peer-ether1 instance=default templates=ebgp-default local.address=vlan101 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-ether2 instance=default templates=ebgp-default local.address=vlan102 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-ether3 instance=default templates=ebgp-default local.address=vlan103 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-ether4 instance=default templates=ebgp-default local.address=vlan104 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-ether5 instance=default templates=ebgp-default local.address=vlan105 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-ether6 instance=default templates=ebgp-default local.address=vlan106 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-sfp1 instance=default templates=ebgp-default local.address=vlan107 .role=ebgp output.network=bgp-networks disabled=yes
/routing bgp connection add name=peer-sfp2 instance=default templates=ebgp-default local.address=vlan108 .role=ebgp output.network=bgp-networks disabled=yes
