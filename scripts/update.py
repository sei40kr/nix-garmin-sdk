#!/usr/bin/env python3
"""Update sources.json to the latest Connect IQ SDKs and SDK Manager for Linux.

Usage: update.py [--file sources.json] [--force] [--min-major N]

Tracks the newest release of every SDK release line (major version) from
--min-major on, since devices that stop receiving firmware updates are capped
at older SDK lines. Reads Garmin's release feeds, prefetches changed archives
into the Nix store and rewrites sources.json. The SDK Manager is published under a fixed URL that
Garmin may overwrite without bumping the version, so its (small) archive is
always re-hashed.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

BASE = os.environ.get(
    "CONNECTIQ_DOWNLOAD_BASE", "https://developer.garmin.com/downloads/connect-iq"
)
SDKS_URL = f"{BASE}/sdks/sdks.json"
MANAGER_URL = f"{BASE}/sdk-manager/sdk-manager.json"
MANAGER_ZIP = "connectiq-sdk-manager-linux.zip"
# Oldest SDK line whose Linux binaries use the GTK 3 / WebKitGTK 4.0 stack this
# flake knows how to run.
DEFAULT_MIN_MAJOR = 4

LINUX_SDK_RE = re.compile(
    r"^connectiq-sdk-lin-(?P<version>\d+(?:\.\d+)+)-(?P<release>\d{4}-\d{2}-\d{2})-(?P<rev>[0-9a-f]+)\.zip$"
)


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "nix-garmin-sdk-updater"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def version_key(version):
    return tuple(int(p) for p in version.split("."))


def prefetch(url):
    out = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", "--hash-type", "sha256", url],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(out)["hash"]


def latest_sdks(min_major):
    """Newest Linux SDK of each major version >= min_major, keyed by major."""
    latest = {}
    for entry in fetch_json(SDKS_URL):
        m = LINUX_SDK_RE.match(entry.get("linux") or "")
        if not m:
            continue
        sdk = {
            "version": m["version"],
            "release": m["release"],
            "url": f"{BASE}/sdks/{entry['linux']}",
        }
        major = m["version"].split(".")[0]
        if int(major) < min_major:
            continue
        if major not in latest or version_key(sdk["version"]) > version_key(latest[major]["version"]):
            latest[major] = sdk
    if not latest:
        sys.exit(f"no Linux SDK >= {min_major} found in {SDKS_URL}")
    return latest


def latest_manager():
    info = fetch_json(MANAGER_URL)
    version = info.get("version")
    if not version:
        sys.exit(f"no version in {MANAGER_URL}: {info!r}")
    filename = info.get("linux") or MANAGER_ZIP
    if not filename.startswith(("http://", "https://")):
        filename = f"{BASE}/sdk-manager/{filename}"
    return {"version": version, "url": filename}


def update_entry(name, old, new, force):
    unchanged = old.get("version") == new["version"] and old.get("url") == new["url"]
    if unchanged and not force and old.get("hash"):
        print(f"{name}: {new['version']} is up to date")
        return old, False
    print(f"{name}: {old.get('version')} -> {new['version']}, hashing {new['url']}")
    new = dict(new, hash=prefetch(new["url"]))
    return new, new != old


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--file", default="sources.json")
    ap.add_argument("--force", action="store_true", help="re-prefetch even if versions match")
    ap.add_argument(
        "--min-major",
        type=int,
        default=DEFAULT_MIN_MAJOR,
        help=f"oldest SDK major version to package (default {DEFAULT_MIN_MAJOR})",
    )
    args = ap.parse_args()

    try:
        with open(args.file) as f:
            sources = json.load(f)
    except FileNotFoundError:
        sources = {}

    old_sdks = sources.get("sdks", {})
    sdks = {}
    changed = False
    for major, sdk in sorted(latest_sdks(args.min_major).items(), key=lambda kv: int(kv[0])):
        sdks[major], c = update_entry(f"sdk {major}", old_sdks.get(major, {}), sdk, args.force)
        changed |= c
    for major in old_sdks.keys() - sdks.keys():
        print(f"sdk {major}: dropped")
        changed = True
    manager, manager_changed = update_entry(
        "sdkManager", sources.get("sdkManager", {}), latest_manager(), force=True
    )

    if not (changed or manager_changed):
        return
    sources = {"sdks": sdks, "sdkManager": manager}
    with open(args.file, "w") as f:
        json.dump(sources, f, indent=2)
        f.write("\n")
    print(f"wrote {args.file}")


if __name__ == "__main__":
    main()
