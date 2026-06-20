#!/usr/bin/env python3
"""Compute the CIDR allowlist for smol-pi.

We want to ALLOW the public internet and BLOCK private networks, expressed
as a set of --allow-cidr flags to smolvm (which is allowlist-only).

The blocked (excluded) ranges are:
  IPv4: RFC1918 (10/8, 172.16/12, 192.168/16), CGNAT (100.64/10), link-local
        (169.254/16)
  IPv6: ULA (fc00::/7), link-local (fe80::/10)

Loopback (127.0.0.0/8, ::1) is deliberately NOT excluded: smolvm's userspace
proxy (passt/gvproxy) does not forward guest loopback to the host, so the
guest's 127.0.0.1 is its own loopback, not the host's. Excluding it from the
allowlist would only inflate the flag count (~128 extra IPv6 CIDRs for ::1
alone) without adding any real security.

Output: a single line of space-separated CIDRs, suitable for pasting into
the smol-pi script's ALLOW_CIDRS variable.
"""

import ipaddress

EXCLUDED_V4 = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("100.64.0.0/10"),
]

EXCLUDED_V6 = [
    ipaddress.ip_network("fc00::/7"),
    ipaddress.ip_network("fe80::/10"),
]


def complement(excluded, full):
    remaining = [full]
    for net in excluded:
        new_remaining = []
        for r in remaining:
            if net.overlaps(r):
                new_remaining.extend(r.address_exclude(net))
            else:
                new_remaining.append(r)
        remaining = list(ipaddress.collapse_addresses(new_remaining))
    return remaining


def main():
    v4 = complement(EXCLUDED_V4, ipaddress.ip_network("0.0.0.0/0"))
    v6 = complement(EXCLUDED_V6, ipaddress.ip_network("::/0"))
    all_cidrs = [str(c) for c in v4 + v6]
    print(f"# IPv4: {len(v4)} CIDRs, IPv6: {len(v6)} CIDRs, total: {len(all_cidrs)}")
    print("ALLOW_CIDRS=\"" + " ".join(all_cidrs) + "\"")

    # Sanity checks
    def contains(cidrs, ip):
        addr = ipaddress.ip_address(ip)
        return any(addr in c for c in cidrs)

    assert not contains(v4, "10.1.2.3")
    assert contains(v4, "9.9.9.9")
    assert contains(v4, "1.1.1.1")
    assert not contains(v4, "192.168.1.1")
    assert not contains(v4, "172.16.0.1")
    assert not contains(v4, "100.64.0.1")
    assert not contains(v4, "169.254.1.1")
    assert not contains(v6, "fc00::1")
    assert not contains(v6, "fe80::1")
    assert contains(v6, "2606:6d00::1")
    assert contains(v6, "2607:f8b0::1")
    print("# Sanity checks passed", file=__import__("sys").stderr)


if __name__ == "__main__":
    main()