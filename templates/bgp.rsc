# bgp.rsc — BGP configuration for CRS310-8G+2S+
# Variables: AS, ROUTER_ID, LINK_LOCAL
# LINK_LOCAL is discovered at runtime by deploy.sh after base.rsc creates the VLAN interfaces.

# --- BGP instance ---
/routing bgp instance add name=default as=${AS} router-id=${ROUTER_ID}

# --- BGP template ---
# afi=ip,ipv6: IPv4 routes via Extended Next Hop (ENHE), IPv6 native
# BFD disabled: RouterOS BFD over link-local doesn't establish with FRR (known issue)
/routing bgp template add name=ebgp-default as=${AS} afi=ip,ipv6 use-bfd=no

# --- BFD (disabled — kept for future use) ---
/routing bfd configuration add disabled=no min-rx=1s min-tx=1s multiplier=3

# --- Peer connections (all disabled, ready for activation) ---
# Two-step add/set: RouterOS 7.22 chokes on local.address with %interface in add.
# To activate a peer: set remote.address and remote.as, then enable.

/routing bgp connection add name=peer-ether1 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether1 local.address=${LINK_LOCAL}%vlan101

/routing bgp connection add name=peer-ether2 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether2 local.address=${LINK_LOCAL}%vlan102

/routing bgp connection add name=peer-ether3 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether3 local.address=${LINK_LOCAL}%vlan103

/routing bgp connection add name=peer-ether4 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether4 local.address=${LINK_LOCAL}%vlan104

/routing bgp connection add name=peer-ether5 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether5 local.address=${LINK_LOCAL}%vlan105

/routing bgp connection add name=peer-ether6 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-ether6 local.address=${LINK_LOCAL}%vlan106

/routing bgp connection add name=peer-sfp1 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-sfp1 local.address=${LINK_LOCAL}%vlan107

/routing bgp connection add name=peer-sfp2 instance=default templates=ebgp-default local.role=ebgp disabled=yes
/routing bgp connection set peer-sfp2 local.address=${LINK_LOCAL}%vlan108
