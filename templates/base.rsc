# base.rsc — L2/L3 configuration for CRS310-8G+2S+
# Expects: factory default config (bridge "bridge" with all ports)
# Variables: DEVICE_NAME, MGMT_IP

# --- System ---
/system identity set name=${DEVICE_NAME}
/system clock set time-zone-name=Europe/Berlin

# --- Ethernet: L2MTU + MTU ---
# L2MTU 10218 on all ports so the bridge inherits maximum L2MTU.
# MTU 9000 on peering ports for jumbo frames. Management ports keep MTU 1500.
# WARNING: L2MTU changes cause a switch chip reset and brief connectivity drop.
/interface ethernet set [find default-name=ether1] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether2] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether3] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether4] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether5] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether6] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=ether7] l2mtu=10218
/interface ethernet set [find default-name=ether8] l2mtu=10218
/interface ethernet set [find default-name=sfp-sfpplus1] l2mtu=10218 mtu=9000
/interface ethernet set [find default-name=sfp-sfpplus2] l2mtu=10218 mtu=9000

# --- Bridge VLAN setup ---
# Disable VLAN filtering first (re-enable after table is populated)
/interface bridge set bridge vlan-filtering=no

# PVIDs: each peering port gets a unique VLAN for isolation
/interface bridge port set [find interface=ether1] pvid=101
/interface bridge port set [find interface=ether2] pvid=102
/interface bridge port set [find interface=ether3] pvid=103
/interface bridge port set [find interface=ether4] pvid=104
/interface bridge port set [find interface=ether5] pvid=105
/interface bridge port set [find interface=ether6] pvid=106
/interface bridge port set [find interface=sfp-sfpplus1] pvid=107
/interface bridge port set [find interface=sfp-sfpplus2] pvid=108

# VLAN table: tagged on bridge (CPU sees the traffic), untagged on physical port
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether1 vlan-ids=101
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether2 vlan-ids=102
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether3 vlan-ids=103
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether4 vlan-ids=104
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether5 vlan-ids=105
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether6 vlan-ids=106
/interface bridge vlan add bridge=bridge tagged=bridge untagged=sfp-sfpplus1 vlan-ids=107
/interface bridge vlan add bridge=bridge tagged=bridge untagged=sfp-sfpplus2 vlan-ids=108
/interface bridge vlan add bridge=bridge tagged=bridge untagged=ether7,ether8 vlan-ids=1

# --- VLAN interfaces ---
/interface vlan add interface=bridge name=vlan1 vlan-id=1
/interface vlan add interface=bridge name=vlan101 vlan-id=101 mtu=9000
/interface vlan add interface=bridge name=vlan102 vlan-id=102 mtu=9000
/interface vlan add interface=bridge name=vlan103 vlan-id=103 mtu=9000
/interface vlan add interface=bridge name=vlan104 vlan-id=104 mtu=9000
/interface vlan add interface=bridge name=vlan105 vlan-id=105 mtu=9000
/interface vlan add interface=bridge name=vlan106 vlan-id=106 mtu=9000
/interface vlan add interface=bridge name=vlan107 vlan-id=107 mtu=9000
/interface vlan add interface=bridge name=vlan108 vlan-id=108 mtu=9000

# --- Enable VLAN filtering ---
# MUST be after VLAN table + interfaces are populated to avoid lockout
/interface bridge set bridge vlan-filtering=yes

# --- IPv6 ND prefixes for unnumbered BGP ---
# Each peering VLAN needs an ND prefix so the switch sends Router Advertisements,
# enabling peers to auto-discover the switch's link-local address (RFC 4861).
/ipv6 nd prefix add prefix=none interface=vlan101
/ipv6 nd prefix add prefix=none interface=vlan102
/ipv6 nd prefix add prefix=none interface=vlan103
/ipv6 nd prefix add prefix=none interface=vlan104
/ipv6 nd prefix add prefix=none interface=vlan105
/ipv6 nd prefix add prefix=none interface=vlan106
/ipv6 nd prefix add prefix=none interface=vlan107
/ipv6 nd prefix add prefix=none interface=vlan108

# --- IPv6: accept RAs even with forwarding enabled (for SLAAC from upstream) ---
/ipv6 settings set accept-router-advertisements=yes

# --- Management IP on vlan1 (not on bridge — see docs/architecture.md) ---
/ip address add address=${MGMT_IP} interface=vlan1

# --- DHCP client for upstream connectivity ---
/ip dhcp-client add interface=vlan1

# --- MSS clamping (safety net when PMTUD fails) ---
/ip firewall mangle add action=change-mss chain=forward new-mss=clamp-to-pmtu protocol=tcp tcp-flags=syn
/ipv6 firewall mangle add action=change-mss chain=forward new-mss=clamp-to-pmtu protocol=tcp tcp-flags=syn

# --- L3 hardware offloading ---
/interface ethernet switch set 0 l3-hw-offloading=yes
/interface ethernet switch l3hw-settings set ipv6-hw=yes
