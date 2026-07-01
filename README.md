# smol-pi

```
  ███████╗███╗   ███╗ ██████╗ ██╗      ██████╗ ██╗
  ██╔════╝████╗ ████║██╔═══██╗██║      ██╔══██╗██║
  ███████╗██╔████╔██║██║   ██║██║█████╗██████╔╝██║
  ╚════██║██║╚██╔╝██║██║   ██║██║╚════╝██╔═══╝ ██║
  ███████║██║ ╚═╝ ██║╚██████╔╝███████╗ ██║     ██║
  ╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝ ╚═╝     ╚═╝
```

An ephemeral microVM sandbox for the [pi coding agent](https://npmjs.com/package/@earendil-works/pi-coding-agent), built on [smolvm](https://smolmachines.com).

pi runs inside a lightweight VM with its own kernel. Your project directory and `~/.pi` are mounted in; everything else is isolated. When pi exits, the VM is gone — no persistent state, no leftover processes, no host pollution.

## Why

Running an AI coding agent directly on your machine means it has access to your home directory, your SSH keys, your environment variables, and your network. smol-pi puts it in a disposable VM instead:

- **Filesystem isolation**: the agent sees `/workspace` (your project) and `~/.pi` (its config). Not your home directory, not your dotfiles, not your browser profile.
- **Network isolation**: four egress modes, from "block private networks" (default) to "block everything except specific hosts."
- **Ephemeral**: nothing persists across runs except what's in the mounted directories. No `apt install` leaking onto your host. No background processes surviving.

## Prerequisites

- **smolvm** — the microVM runtime. Install: `curl -sSL https://smolmachines.com/install.sh | bash`
- **podman or docker** — needed to build the sandbox image and run pi subcommands. podman is preferred (rootless, no daemon).
- **Linux** with KVM (x86_64 or arm64). macOS support is expected but untested — see [TODO](TODO.md) item "macOS testing."

## Install

```sh
curl -sSL https://raw.githubusercontent.com/neuroblaze/smol-pi/v1.0.1/install.sh | sh
```

Prefer to read it first?

```sh
curl -sSL -o install.sh https://raw.githubusercontent.com/neuroblaze/smol-pi/v1.0.1/install.sh
less install.sh
sh install.sh
```

This downloads `smol-pi`, `smol-pi-build`, and `Dockerfile.pi` to `~/.local/bin/` (override with `--prefix <dir>`). The installer is pinned to a release tag, so the files you get are immutable and reproducible.

To install a different release:

```sh
sh install.sh --version v1.0.0          # specific tag
sh install.sh --version latest          # auto-resolve newest release
sh install.sh --list-versions           # print available release tags
```

## Build the sandbox image

```sh
smol-pi-build
```

This builds the `pi-sandbox` container image using podman (or docker) and exports it as `pi-sandbox.tar`. The build uses `--no-cache`, so re-running it always pulls fresh base images and picks up upstream updates to pi, uv, and the base OS.

The image is based on `node:24-trixie-slim` and includes:

- The pi coding agent (`@earendil-works/pi-coding-agent`)
- [uv](https://github.com/astral-sh/uv) for Python work
- QoL utilities: curl, ripgrep, jq, git, vim, less, file, make, rsync, ssh, sudo, etc.

### Custom images

You can build a custom image with additional packages or tools. Start by generating the default Dockerfile to edit:

```sh
smol-pi-build --generate-dockerfile    # writes Dockerfile.pi to CWD
```

Then modify it to suit your needs. For example, to add Python and Rust:

```dockerfile
FROM node:24-trixie-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       bash ca-certificates coreutils curl file findutils git gnupg \
       iproute2 jq fd-find less \
       make openssh-client procps ripgrep rsync \
       sudo tar unzip vim xz-utils zstd \
       python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

RUN printf '%s\n' \
    '#!/bin/sh' \
    '# smol-pi entrypoint: optionally rewrite DNS, set TTY size, cd to /workspace,' \
    '# then exec.' \
    '# smolvm allocates the PTY at 24x80 by default. If COLUMNS/LINES env vars are' \
    '# set (passed from the host terminal via smol-pi), resize the PTY to match.' \
    '# This only affects the initial size — terminal resize signals still work.' \
    'if [ -n "$SMOL_PI_DNS" ]; then' \
    '  echo "nameserver $SMOL_PI_DNS" > /etc/resolv.conf' \
    'fi' \
    'if [ -n "$COLUMNS" ] && [ -n "$LINES" ]; then' \
    '  stty rows "$LINES" cols "$COLUMNS" 2>/dev/null' \
    'fi' \
    'cd /workspace 2>/dev/null || true' \
    'exec "$@"' \
  > /usr/local/bin/smol-pi-entrypoint \
  && chmod +x /usr/local/bin/smol-pi-entrypoint

WORKDIR /workspace
ENTRYPOINT ["pi"]
```

Then build with your custom Dockerfile:

```sh
smol-pi-build -f ./Dockerfile.pi
```

The built `pi-sandbox.tar` is written next to the `smol-pi-build` script (typically `~/.local/bin/`). `smol-pi` looks for the image there automatically. The `--no-cache` flag ensures a clean build each time, and orphaned image archives from previous builds are cleaned up automatically.

If you want to keep multiple images, use `--image-tag` to name them:

```sh
smol-pi-build -f ./Dockerfile.custom --image-tag pi-custom
```

The image tag only affects the container image name during build — `smol-pi` always loads `pi-sandbox.tar` regardless of the tag used to build it.

#### Installing pi extensions

Pi extensions (via `pi install`) are stored in `~/.pi/agent/`, which is a bind mount from the host — not baked into the image. So installing extensions in the Dockerfile won't work; they'll be shadowed by the mount at runtime. Install extensions after the image is built instead:

```sh
smol-pi install @anthropic/plan-mode
```

This runs via the podman/docker fast path (no VM boot) and writes directly to `~/.pi` on the host, where the VM will pick it up on the next run.

## Run

```sh
smol-pi                    # drop into pi interactively
smol-pi -p "fix the bug"   # run pi with a prompt
smol-pi --shell            # drop into a plain shell instead of pi
```

Your current working directory is mounted at `/workspace`. `~/.pi` is mounted at `/root/.pi` read-write (so pi can persist config/auth across runs). Everything else inside the VM is ephemeral.

## Pi subcommands

Pi has subcommands that only manage the `~/.pi` directory — they don't invoke the agent and don't need a full VM:

```sh
smol-pi install <package>   # install a pi extension
smol-pi remove <package>    # remove an extension
smol-pi list                # list installed extensions
smol-pi config              # open the resource configuration TUI
```

These run via podman or docker directly (no VM boot), so they're nearly instant. The `~/.pi` directory and current working directory are mounted into the container. With docker, the container runs as your host UID to avoid creating root-owned files in `~/.pi`.

Note that while `smol-pi update` will run, changes will not persist, since they will be made in the ephemeral VM. If you want to update pi to the latest version, run `smol-pi-build` to rebuild the container.

## Network modes

```sh
smol-pi --network-mode block-local    # default: internet allowed, private networks blocked
smol-pi --network-mode block-all      # all egress blocked
smol-pi --network-mode block-internet # private networks allowed, internet blocked
smol-pi --network-mode allow-all      # everything allowed
```

| Mode | Public internet | Private networks | DNS | Use case |
|------|-----------------|-------------------|-----|----------|
| `block-local` (default) | allowed | blocked | forced to 1.1.1.1 | General use — agent can reach APIs but not your LAN |
| `block-all` | blocked | blocked | filtered to allowed hosts | Maximum lockdown — punch holes with `--allow-host` |
| `block-internet` | blocked | allowed | system (injected) | Internal/corporate environments |
| `allow-all` | allowed | allowed | system (injected) | No restrictions, pure isolation |

### Punching holes in block-all

```sh
smol-pi --network-mode block-all --allow-host api.anthropic.com
```

`--allow-host` is only valid with `block-all`. In the CIDR-based modes (`block-local`, `block-internet`) it triggers smolvm's DNS filtering, which breaks general hostname resolution.

### DNS override

```sh
smol-pi --dns 1.1.1.1                  # override DNS in any mode
```

By default, `block-local` forces 1.1.1.1 (the system DNS is typically at your LAN gateway, which is a blocked private IP). All other modes use the system DNS that smolvm injects at boot, so internal hostnames resolve. Use `--dns` to override in any mode.

## Options

```
smol-pi                       Drop into pi interactively
smol-pi <pi-args>              Run pi with args (e.g. smol-pi -p "fix the bug")
smol-pi --shell                Drop into a plain shell (/bin/sh) instead of pi
smol-pi --pi-dir <path>        Use an alternate .pi directory (default: ~/.pi)
smol-pi --network-mode <mode>  Set network egress mode (default: block-local)
smol-pi --allow-host <host>    Allow egress to a specific host (block-all only)
smol-pi --dns <server>         Override DNS server (default: mode-dependent)
smol-pi clean                   Remove stale smolvm cache (frees disk space)
smol-pi --help                  Show this help
```

Memory: 4 GiB (elastic via virtio-balloon).

## How it works

1. `smol-pi-build` creates an OCI image (`pi-sandbox.tar`) containing the pi agent and a custom entrypoint (`smol-pi-entrypoint`) that handles DNS configuration and terminal sizing.
2. `smol-pi` invokes `smolvm machine run` with the image, your project mounted at `/workspace`, `~/.pi` mounted at `/root/.pi`, and network flags corresponding to the chosen mode.
3. smolvm boots a real Linux kernel in a microVM (KVM on Linux, Hypervisor.framework on macOS), with network egress filtered by a userspace proxy (passt).
4. When the command exits, the VM is destroyed. Only the mounted directories persist.

## Disk cleanup

smolvm >= 1.3.1 cleans up ephemeral VM state automatically on graceful exit ([smolvm#497](https://github.com/smol-machines/smolvm/pull/497)). Earlier versions leaked ~1.4 GB of VM state (qcow2 disks, logs) per `machine run` into `~/.cache/smolvm/vms/`, and image archives accumulate in `~/.cache/smolvm-image-archives/` across builds.

smol-pi keeps a safety net for the cases smolvm can't handle itself:

- **Orphaned processes**: if smol-pi is `SIGKILL`'d (OOM killer, `kill -9`), the smolvm process can't run its cleanup. The next `smol-pi` run detects and kills any orphaned `smolvm-bin` using the same image before booting.
- **`smol-pi-build`**: orphaned image archives from previous builds are removed after a rebuild (applies on any smolvm version).
- **`smol-pi clean`**: manual reclamation of stale VM dirs and orphaned image archives, for crash recovery or smolvm < 1.3.1.

```sh
smol-pi clean
```

This removes all stale VM dirs and orphaned image archives, keeping only the archive matching the current `pi-sandbox.tar`.

## Orphaned VM processes

If the smol-pi script is killed with `SIGKILL` (OOM killer, `kill -9`), smolvm can't run its graceful-exit cleanup and the smolvm process may stay running, consuming ~2 GB RSS. The next `smol-pi` run detects and kills any orphaned `smolvm-bin` process using the same image before booting. Normal exits and trappable signals (Ctrl+C, terminal close, SSH disconnect) are handled cleanly by smolvm >= 1.3.1 — the VM is terminated and disk state is reclaimed. For leaked disk state after a crash, run `smol-pi clean`.

## Security

### What the agent can see

The agent has full read-write access to two directories:

- **`/workspace`** — your current working directory when you launch smol-pi. Anything in that directory is visible to the agent, including secrets files, `.env` files, private keys, etc. Be mindful of where you invoke smol-pi.
- **`/root/.pi`** — pi's config and auth storage, mounted from `~/.pi` on the host. This contains pi's authentication tokens and any installed extensions.

The agent cannot see your home directory, dotfiles, SSH keys, browser profile, or anything else outside these two mounts. The VM has its own kernel, so the agent cannot access host kernel features or devices.

### Secrets isolation is out of scope

The `~/.pi` directory contains API keys and auth tokens. We don't try to hide these from the agent — in this setup, true secrets isolation is theatre. The agent can always read environment variables (`printenv`), inspect `/proc/*/environ`, or exfil secrets through file reads. Any mechanism that gives the agent a secret to use also gives it the ability to leak that secret.

If you need real secrets isolation, route API calls through a local proxy that injects credentials out-of-band, so the agent never sees the key material. This is a user/infrastructure concern, not something smol-pi can solve inside the sandbox.

### Network egress

Network egress is the main attack surface. The default `block-local` mode allows public internet (so the agent can reach LLM APIs, package registries, etc.) but blocks private networks (your LAN, RFC1918, link-local, CGNAT, ULA). This prevents a compromised agent from reaching internal services on your network.

For maximum lockdown, use `block-all` with `--allow-host` to punch holes only to specific hosts (e.g. your LLM API endpoint).

### Building safely

The `--no-cache` build ensures you get fresh base images, but you should still rebuild periodically to pick up security updates in the base OS and pi itself.

## Files

| File | Description |
|------|-------------|
| `smol-pi` | Launcher script — boots the VM with network/DNS config |
| `smol-pi-build` | Image builder — podman/docker, `--no-cache`, embeds the Dockerfile |
| `Dockerfile.pi` | Image definition — node:24-trixie-slim + pi + uv + QoL utils |
| `install.sh` | One-line installer — downloads scripts, checks prereqs |
| `scripts/compute_cidrs.py` | CIDR allowlist generator with sanity checks |
| `TODO` | Improvement ideas and findings |

## License

MIT-0 (public domain equivalent). See [LICENSE](LICENSE).

Copyright (c) 2026 Peter Kazakoff
