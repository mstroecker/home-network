#!/bin/sh
# Stand-in for the Fritz!Box: hands out DHCP on 192.168.178.0/24 to the switch
# uplinks and NATs their traffic out the mgmt interface (eth0) to the real
# internet. Runs once via the node's `exec:` after the data links are wired.
set -e

apk add --no-cache iptables dnsmasq >/dev/null 2>&1

# Bridge both switch-facing uplinks into one L2 segment = 192.168.178.0/24.
ip link add br-lan type bridge 2>/dev/null || true
ip link set eth1 master br-lan
ip link set eth2 master br-lan
ip link set br-lan up
ip addr add 192.168.178.1/24 dev br-lan 2>/dev/null || true

# DHCP: gateway = .1, public DNS (matches the production "no Fritz!Box DNS" note).
dnsmasq \
  --interface=br-lan --bind-interfaces \
  --dhcp-range=192.168.178.10,192.168.178.100,12h \
  --dhcp-option=3,192.168.178.1 \
  --dhcp-option=6,1.1.1.1,1.0.0.1

# Forward + masquerade toward the outside world.
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -C FORWARD -i br-lan -o eth0 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i br-lan -o eth0 -j ACCEPT
iptables -C FORWARD -i eth0 -o br-lan -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i eth0 -o br-lan -m state --state RELATED,ESTABLISHED -j ACCEPT
