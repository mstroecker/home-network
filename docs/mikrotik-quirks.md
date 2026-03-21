# Mikrotik quirks and pitfalls

**Priority:** Reference

A collection of Mikrotik-specific behaviors relevant to this setup. Not all are bugs — some are just things to keep in mind.

## /import stops on first error

If any command in a `.rsc` file fails, all subsequent commands are skipped.

**Mitigation:** Validate rendered templates before deploying (e.g., check for un-substituted `${...}` patterns).

## suppress-hw-offload pulls ECMP partners out of hardware

When a `suppress-hw-offload` route forms an ECMP pair with an HW-offloaded route (same dst, gateway, distance), the HW-offloaded route loses its `H` flag too — both routes are processed in CPU. Verified on CRS310 with RouterOS 7.22: the DHCP default route is HW-offloaded when alone, but adding the `suppress-hw-offload` static route pulls it out of hardware. This is why masquerade NAT works for peer internet traffic.

## BFD runs in CPU on CRS310

The CRS310's Marvell chip doesn't offload BFD to hardware. With 1s min-rx/min-tx and multiplier 3 (3s detection), false positives are unlikely under normal load. But if the CPU is saturated (heavy NAT, route convergence, many peers), BFD could time out and flap BGP sessions.

Worth monitoring if you scale beyond a few peers or increase NAT traffic volume.

## DHCP client + static IP on same interface

Having both a static IP (`192.168.89.1/24`) and DHCP (`192.168.178.x/24`) on vlan1 means outgoing packets use RouterOS's source-address selection. For masquerade NAT this works correctly (picks the address matching the outgoing route's subnet). For non-NATted traffic from the switch itself, the source IP depends on the destination.

## Bridge VLAN filtering boot race

Correctly handled in this setup (management IP on vlan1 interface, not bridge). Just noting it as one of the most common Mikrotik lockout causes — never move the management IP to the bridge interface directly.

## DX3000 MAC address constraint

When using L3HW with multiple MTU profiles, the switch chip only allows the last octet of the MAC address to differ between interfaces. Documented in docs/architecture.md. Not an issue unless you manually assign MACs to VLAN interfaces.

## ENHE limitations are RouterOS-specific

The ENHE bug (IPv4 next-hop leak on redistributed routes, `0.0.0.0/0` as wildcard in address lists, default-originate ignoring ENHE) is RouterOS behavior, not a protocol limitation. FRR handles ENHE correctly. Worth re-testing on future RouterOS versions — these may get fixed.
