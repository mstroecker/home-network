# mikrotik-vm — RouterOS CHR image builder

MikroTik ships no container image, so containerlab runs RouterOS as a CHR VM
wrapped by [hellt/vrnetlab](https://github.com/hellt/vrnetlab). This folder
automates that one-time build into the image the lab expects:
`vrnetlab/mikrotik_routeros:<version>`.

## Requirements

`docker`, `git`, `make`, `qemu-img` (from `qemu-utils` / `qemu-img`), `python3`
(stdlib only — no pip packages).

## Usage

```bash
make build                 # download 7.23.1, convert, build the image
make build VERSION=7.22    # pin a different version (e.g. match production)
make check                 # is the image present?
make help                  # list all targets
```

Individual steps if you want them: `make download`, `make convert`, `make image`.

The Python script does the work and can be run directly:

```bash
./build.py --version 7.23.1
```

## What it does

1. **download** — `chr-<ver>.img.zip` from
   `download.mikrotik.com/routeros/<ver>/` (the free CHR tier; no license needed
   for a control-plane lab).
2. **convert** — unzip and `qemu-img convert` raw → qcow2.
3. **image** — shallow-clone vrnetlab, drop `chr-<ver>.qcow2` into `routeros/`,
   run its `make`. vrnetlab derives the tag from the filename.

Re-runs are cheap: each step skips work whose output already exists.

## After building

```bash
cd ..                       # back to lab/
sudo clab deploy -t home-network.clab.yml
```

`make clean` removes the downloaded/intermediate files; `make distclean` also
drops the `vrnetlab/` clone.

> If the produced tag differs from `vrnetlab/mikrotik_routeros:<version>`
> (vrnetlab naming occasionally changes), the build prints what it made — retag
> it or update the `image:` line in `../home-network.clab.yml`.
