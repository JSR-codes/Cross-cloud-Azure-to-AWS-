#!/usr/bin/env python3
"""
Pre-migration network readiness check: confirms the source (Azure) VM can
reach the ports AWS MGN needs before you install the replication agent.

MGN's agent needs outbound connectivity to the AWS API endpoint (443) and to
the replication servers it stands up in the staging subnet (1500 by default).
If either is blocked - by an NSG on the Azure side, a firewall in between, or
a missing route - the agent install will look like it succeeds but
replication will never start or will stall at 0%. Catching that here is
faster than debugging it from the MGN console after the fact.

Run this from the Azure source VM, pointed at the AWS side, before Part 3
(installing the replication agent) in the README.

Usage:
    python3 check_network_readiness.py <target_host> [--ports 443,1500]
"""

import argparse
import socket
import time

DEFAULT_PORTS = {
    443: "AWS MGN API / HTTPS",
    1500: "MGN replication agent traffic",
}


def resolve(host: str) -> tuple[bool, str]:
    try:
        ip = socket.gethostbyname(host)
        return True, ip
    except socket.gaierror as exc:
        return False, str(exc)


def check_port(host: str, port: int, timeout: float = 5.0) -> tuple[bool, float]:
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True, time.monotonic() - start
    except OSError:
        return False, time.monotonic() - start


def parse_ports(raw: str) -> list[int]:
    return [int(p.strip()) for p in raw.split(",") if p.strip()]


def main():
    parser = argparse.ArgumentParser(description="Check MGN network readiness before agent install.")
    parser.add_argument("target_host", help="AWS-side host/IP the source VM needs to reach")
    parser.add_argument(
        "--ports",
        default=",".join(str(p) for p in DEFAULT_PORTS),
        help="Comma-separated ports to check (default: 443,1500)",
    )
    args = parser.parse_args()

    print(f"Resolving {args.target_host} ...")
    resolved, detail = resolve(args.target_host)
    if not resolved:
        print(f"  FAIL - DNS resolution failed: {detail}")
        print("\nDo not proceed with agent install until DNS resolves.")
        raise SystemExit(2)
    print(f"  OK - resolves to {detail}")

    print()
    all_ok = True
    for port in parse_ports(args.ports):
        label = DEFAULT_PORTS.get(port, "custom port")
        ok, elapsed = check_port(args.target_host, port)
        status = "OK" if ok else "FAIL"
        print(f"  [{status}] port {port} ({label}) - {elapsed:.2f}s")
        all_ok = all_ok and ok

    print()
    if all_ok:
        print("All checks passed - safe to proceed with agent install (README Part 3).")
    else:
        print("One or more ports are unreachable - fix NSG/firewall/routing before installing the agent.")
        raise SystemExit(2)


if __name__ == "__main__":
    main()
