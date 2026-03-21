# upstream.rsc — NAT and default route for peer internet access
# Variables: UPSTREAM_GW

# --- Masquerade NAT ---
# The upstream router does not know peer prefixes (e.g. 10.65.10.0/24).
# Masquerade rewrites the source to the switch's DHCP address on vlan1.
/ip firewall nat add chain=srcnat out-interface=vlan1 action=masquerade

# --- CPU-processed default route ---
# suppress-hw-offload forces this route (and its DHCP ECMP partner) through the
# CPU so masquerade NAT is applied. Without this, the DHCP default route is
# HW-offloaded and NAT is bypassed entirely.
/ip route add dst-address=0.0.0.0/0 gateway=${UPSTREAM_GW} distance=1 suppress-hw-offload=yes comment=internet-via-cpu
