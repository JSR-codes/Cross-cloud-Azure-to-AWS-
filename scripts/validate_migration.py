#!/usr/bin/env python3
"""
Post-migration validation: confirms the migrated (AWS) instance serves
identical content to the original (Azure) source before you decommission
anything. Run this before and after cutover.

Usage:
    python3 validate_migration.py <source_ip> <target_ip>
"""

import sys
import hashlib
import urllib.request


def fetch_and_hash(ip: str) -> tuple[int, str]:
    url = f"http://{ip}/"
    with urllib.request.urlopen(url, timeout=10) as response:
        body = response.read()
        return response.status, hashlib.sha256(body).hexdigest()


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 validate_migration.py <source_ip> <target_ip>")
        sys.exit(1)

    source_ip, target_ip = sys.argv[1], sys.argv[2]

    print(f"Checking source (Azure)  : {source_ip}")
    source_status, source_hash = fetch_and_hash(source_ip)
    print(f"  status={source_status} sha256={source_hash}")

    print(f"Checking target (AWS)    : {target_ip}")
    target_status, target_hash = fetch_and_hash(target_ip)
    print(f"  status={target_status} sha256={target_hash}")

    print()
    if source_hash == target_hash:
        print("MATCH - migrated content is identical to source. Safe to proceed with cutover.")
    else:
        print("MISMATCH - content differs. Do NOT cut over until this is investigated.")
        sys.exit(2)


if __name__ == "__main__":
    main()
