#!/usr/bin/env python3
"""Build the RouterOS CHR image for containerlab's `mikrotik_ros` kind.

MikroTik publishes no container image, so containerlab runs RouterOS as a CHR
VM wrapped in a container by vrnetlab. This script automates that one-time build:

  1. download  CHR VMDK image (chr-<ver>.vmdk.zip) from mikrotik.com
  2. extract   unzip -> chr-<ver>.vmdk  (vrnetlab consumes .vmdk/.vdi directly)
  3. image     clone hellt/vrnetlab, drop the vmdk in mikrotik/routeros/, run `make`
               -> docker image vrnetlab/mikrotik_routeros:<ver>

Usage:
  ./build.py                 # full flow, default version
  ./build.py --version 7.22  # pin a version
  ./build.py download        # individual steps: download | extract | image
"""
import argparse
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
VRNETLAB_REPO = "https://github.com/hellt/vrnetlab.git"
DOWNLOAD_URL = "https://download.mikrotik.com/routeros/{v}/chr-{v}.vmdk.zip"
DEFAULT_VERSION = "7.22"  # 7.23.1+ hangs at the serial login under vrnetlab (see README)


def run(cmd, cwd=None):
    print(f"$ {' '.join(str(c) for c in cmd)}")
    subprocess.run(cmd, cwd=cwd, check=True)


def need(tool):
    if shutil.which(tool) is None:
        sys.exit(f"error: required tool '{tool}' not found in PATH")


def download(version):
    zip_path = HERE / f"chr-{version}.vmdk.zip"
    if zip_path.exists():
        print(f"already downloaded: {zip_path.name}")
        return zip_path
    url = DOWNLOAD_URL.format(v=version)
    print(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    tmp = zip_path.with_suffix(".part")
    try:
        with urllib.request.urlopen(req) as r, open(tmp, "wb") as f:
            total = int(r.headers.get("Content-Length", 0))
            done = 0
            while chunk := r.read(1 << 16):
                f.write(chunk)
                done += len(chunk)
                if total:
                    print(f"\r  {done >> 20} / {total >> 20} MiB "
                          f"({done * 100 // total}%)", end="")
            print()
    except urllib.error.HTTPError as e:
        tmp.unlink(missing_ok=True)
        sys.exit(f"error: download failed ({e.code} {e.reason}). "
                 f"Check the version exists at mikrotik.com/download.")
    tmp.rename(zip_path)
    return zip_path


def extract(version):
    zip_path = download(version)
    vmdk = HERE / f"chr-{version}.vmdk"
    if vmdk.exists():
        print(f"already extracted: {vmdk.name}")
        return vmdk
    print(f"unzipping {zip_path.name}")
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.endswith(".vmdk")]
        if not names:
            sys.exit(f"error: no .vmdk inside {zip_path.name}: {z.namelist()}")
        z.extract(names[0], HERE)
        extracted = HERE / names[0]
        if extracted != vmdk:
            extracted.replace(vmdk)
    return vmdk


def find_routeros_dir(vr):
    """Locate the routeros build dir. vrnetlab regrouped by vendor, so it moved
    from vrnetlab/routeros to vrnetlab/mikrotik/routeros — try both, then glob."""
    candidates = [vr / "mikrotik" / "routeros", vr / "routeros"]
    candidates += sorted(p.parent for p in vr.glob("**/routeros/Makefile"))
    for c in candidates:
        if (c / "Makefile").is_file():
            return c
    sys.exit(f"error: could not find a routeros/ build dir under {vr} — "
             f"vrnetlab layout may have changed again.")


def build_image(version):
    for t in ("docker", "git", "make"):
        need(t)
    vmdk = extract(version)
    vr = HERE / "vrnetlab"
    if not vr.exists():
        run(["git", "clone", "--depth", "1", VRNETLAB_REPO, vr])
    ros = find_routeros_dir(vr)
    # vrnetlab globs *.vmdk/*.vdi in this dir and builds EVERY match, deriving
    # the tag from each filename. Purge stale disk images so only ours is built.
    for stale in [*ros.glob("chr-*.vmdk"), *ros.glob("chr-*.vdi")]:
        if stale.name != vmdk.name:
            print(f"removing stale build input: {stale.name}")
            stale.unlink()
    shutil.copy2(vmdk, ros / vmdk.name)
    run(["make"], cwd=ros)
    print("\nbuilt RouterOS images:")
    run(["docker", "images", "vrnetlab/mikrotik_routeros"])
    print(f"\nThe topology expects: vrnetlab/mikrotik_routeros:{version}\n"
          f"If the tag above differs, retag it or edit home-network.clab.yml.")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", default="all",
                    choices=["all", "download", "extract", "image"],
                    help="which step to run (default: all)")
    ap.add_argument("--version", default=DEFAULT_VERSION,
                    help=f"RouterOS CHR version (default: {DEFAULT_VERSION})")
    args = ap.parse_args()
    {"download": download, "extract": extract,
     "image": build_image, "all": build_image}[args.step](args.version)


if __name__ == "__main__":
    main()
