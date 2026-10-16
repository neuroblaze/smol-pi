# smol-pi sandbox: default image

Context for an agent running inside a [smol-pi](https://github.com/neuroblaze/smol-pi) sandbox (the default `pi` image). Copy this into your project's `AGENTS.md` so a fresh agent starts with this knowledge instead of rediscovering the sandbox.

## What you are running in

- An **ephemeral micro-VM**, not a container: [smolvm](https://github.com/smol-machines/smolvm) boots a real Linux kernel in a hypervisor via [libkrun](https://github.com/libkrun/libkrun).
- You are **root**, hostname `vm-<random>`. There is no systemd (PID 1 is the VM init), no Docker/Podman, and no `/dev/kvm`, so don't try nested VMs or containers.
- Time is UTC. Defaults: **2 GiB RAM**, a handful of vCPUs, ~20 GB scratch disk. If you hit memory limits, say so rather than fighting them; the user can relaunch with more.
- When the session ends the VM is destroyed.

## Persistence

Exactly two host directories are mounted, and only they survive:

- `/workspace` — the user's project directory (your working directory).
- `/root/.pi` — pi's own directory (config, extensions, helpers).

Everything else (`/tmp`, `/root/.cache`, globally installed packages, `apt-get` installs) lives on a read-only base plus an ephemeral overlay, and is gone when the VM exits. Keep artifacts, virtualenvs, and caches you need again under `/workspace` (or `~/.pi`).

## OS and installed tooling

Debian 13 (trixie), based on `node:24-trixie-slim`; kernel from libkrunfw.

- **Node.js 24 + npm**, and `pi` itself, installed globally.
- **uv/uvx** for Python — but **no system Python, no pip**, and **no C/C++ toolchain** (`gcc`, `cc`, `g++`, `cmake` are absent; `make` is present). `uv venv` / `uv run` works; native modules that need a compiler do not.
- git, openssh-client, curl (no wget), rsync, jq, vim, less, file, tar, unzip, xz, zstd.
- ripgrep (`rg`), `fd`, findutils, procps, sudo (redundant), gnupg, iproute2, `ping`/`tracepath` (both useless here — see below), ca-certificates.

## Networking

smolvm virtualizes networking in user space. Nothing about it behaves like an ordinary NIC, and the surprises depend on the egress mode the user chose.

Two possible backends:

- **Filtered modes** (`block-local` is the default, plus `block-internet` and `block-all`): the guest gets a private virtio-net link — `eth0` with a `100.96.0.x/30` address and a gateway — whose traffic is filtered by a host-side stack. `block-local` allows the public internet but blocks private/LAN ranges (RFC1918, link-local, cloud metadata), so the host and its LAN services are unreachable.
- **`allow-all` mode**: smolvm defaults to libkrun **TSI** (Transparent Socket Impersonation) — socket syscalls are proxied to the host and there is no real network interface. `ip addr` shows only `lo` plus a meaningless `dummy0` holding a TEST-NET-3 address (`203.0.113.x`), and `ip route` has no default route. Outbound TCP/UDP still works.

You can detect which one is active with:

```sh
grep -q tsi_hijack /proc/cmdline && echo TSI || echo virtio-net
```

Things that waste time if you don't know them:

- **Don't use `ping` to test connectivity**: it fails in the default modes (ICMP is dropped) and TSI cannot carry ICMP at all. Use `curl`, `getent hosts`, or a TCP connect instead. `tracepath` is equally useless.
- **Nothing can connect to you** unless the user published a port with `smol-pi --port <host>:<guest>`. When they do, the forwarded connection arrives at a **non-loopback address**, so services must listen on `0.0.0.0`, never `127.0.0.1`.
- **Outbound connections are NAT'd through the host**, so remote servers see the host's address.
- **DNS is rewritten** by smol-pi in `/etc/resolv.conf` (the default mode pins it to Cloudflare's `1.1.1.1`). Don't try to "fix" the resolver; if name resolution is broken, tell the user.
- Port-level egress filtering varies by smolvm version and mode — do not assume a given protocol or port will work. Test it, and if a destination is blocked, ask the user to adjust the network mode (they control it on the host, not from in here).
- Interface-level networking misbehaves by design: interface enumeration, binding to a device, VPNs, raw sockets, ICMP-based tools. That is the virtualization, not a broken system.
- If the user enabled `--ssh-agent`, `git`/`ssh` may work against their configured hosts without key material in the VM; don't rely on it being present.

## Working effectively here

- Prefer project-local installs and artifacts under `/workspace`; anything installed system-wide disappears with the VM.
- This is a small VM: be conservative with parallelism and memory-hungry builds.
- You cannot change the sandbox from inside (network mode, mounts, memory, image). If you need different resources, ask the user to relaunch `smol-pi` with different flags.
