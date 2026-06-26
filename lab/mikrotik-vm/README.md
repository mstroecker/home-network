# mikrotik-vm — RouterOS CHR image builder

MikroTik ships no container image, so containerlab runs RouterOS as a CHR VM
wrapped by [hellt/vrnetlab](https://github.com/hellt/vrnetlab). This folder
automates that one-time build into the image the lab expects:
`vrnetlab/mikrotik_routeros:<version>`.

## Requirements

`docker`, `git`, `make`, `python3` (stdlib only — no pip packages).

## Usage

```bash
make build                 # download 7.22, extract, build the image
make build VERSION=7.23.1   # pin another version (but see "Version compatibility")
make check                 # is the image present?
make help                  # list all targets
```

Individual steps if you want them: `make download`, `make extract`, `make image`.

The Python script does the work and can be run directly:

```bash
./build.py --version 7.22
```

## What it does

1. **download** — `chr-<ver>.vmdk.zip` from
   `download.mikrotik.com/routeros/<ver>/` (the free CHR tier; no license needed
   for a control-plane lab).
2. **extract** — unzip to `chr-<ver>.vmdk` (vrnetlab consumes `.vmdk`/`.vdi`
   directly; it globs `*.vmdk` in its build dir, so stale images are purged first).
3. **image** — shallow-clone vrnetlab, drop the vmdk into `mikrotik/routeros/`,
   run its `make`. vrnetlab derives the tag from the filename.

Re-runs are cheap: each step skips work whose output already exists.

## Version compatibility

**Build 7.22, not the latest.** The lab pins `vrnetlab/mikrotik_routeros:7.22`
(also what the production hardware runs). Newer releases — confirmed with
**7.23.1** — build into an image fine but **fail to boot under vrnetlab**:

- The CHR VM starts and prints its banner (`MikroTik 7.23.1 (stable)`) to the
  serial console, then goes silent — it never presents the `MikroTik Login:`
  prompt that vrnetlab's bootstrap waits for.
- vrnetlab's `bootstrap_spin()` watches the serial for that login string; after
  ~300 one-second polls with no match it kills and restarts the VM, so the
  container loops forever as `unhealthy` and the config is never pushed.
- KVM and host RAM are not the cause (the VM boots; KVM is available). It's a
  mismatch between the newer RouterOS console behavior and vrnetlab's
  expect-string bootstrap — i.e. bleeding-edge RouterOS landed before vrnetlab
  caught up.

If you must run a newer version, you'd need a vrnetlab with updated console
handling for it (check upstream), then `make build VERSION=<x>` and update the
`image:` line in `../home-network.clab.yml`.

## After building

```bash
cd ..                       # back to lab/
clab deploy -t home-network.clab.yml
```

`make clean` removes the downloaded/intermediate files; `make distclean` also
drops the `vrnetlab/` clone.

> If the produced tag differs from `vrnetlab/mikrotik_routeros:<version>`
> (vrnetlab naming occasionally changes), the build prints what it made — retag
> it or update the `image:` line in `../home-network.clab.yml`.
