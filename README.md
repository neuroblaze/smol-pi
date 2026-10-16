# smol-pi

```
  ███████╗███╗   ███╗ ██████╗ ██╗      ██████╗ ██╗
  ██╔════╝████╗ ████║██╔═══██╗██║      ██╔══██╗██║
  ███████╗██╔████╔██║██║   ██║██║█████╗██████╔╝██║
  ╚════██║██║╚██╔╝██║██║   ██║██║╚════╝██╔═══╝ ██║
  ███████║██║ ╚═╝ ██║╚██████╔╝███████╗ ██║     ██║
  ╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝ ╚═╝     ╚═╝
```

An ephemeral microVM sandbox for the [pi coding agent](https://pi.dev), built on [smolvm](https://smolmachines.com).

pi runs inside a lightweight VM with its own kernel. Your project directory and `~/.pi` are mounted in; everything else is isolated. When pi exits, the VM is deleted.

## Why

Running an AI coding agent directly on your machine means it has access to your home directory, your SSH keys, your environment variables, and your network. Many harnesses work around this with an approve/deny prompt, which is infamously error prone. smol-pi puts the pi harness in a disposable VM instead:

- **Kernel isolation**: smolvm uses [libkrun](https://github.com/libkrun/libkrun) under the hood, which boots a real stripped-down Linux kernel in a hypervisor. Escaping a hypervisor is much harder than escaping a container.
- **Filesystem isolation**: the agent only sees your project directory (mounted as `/workspace`) and `~/.pi` (pi's config & plugin directory) via virtiofs mounts.
- **Network isolation**: four egress modes, from "block private networks" (default) to "block everything except specific hosts."
- **Ephemeral**: nothing persists across runs except what's in the mounted directories. No `apt install` leaking onto your host. No background processes surviving.

## How it works

1. `smol-pi-build` creates an OCI image (e.g. `pi.tar`) containing the pi agent and a custom entrypoint (`smol-pi-entrypoint`) that handles DNS configuration, terminal sizing, and (on desktop images) starting the virtual desktop.
2. `smol-pi` invokes `smolvm machine run` with the image, your project mounted at `/workspace`, `~/.pi` mounted at `/root/.pi`, and network flags corresponding to the chosen mode.
3. smolvm boots a real Linux kernel in a microVM (KVM on Linux, Hypervisor.framework on macOS), with network egress filtered by smolvm's userspace network stack.
4. When the command exits, the VM is destroyed. Only the mounted directories persist.

## Prerequisites

- **smolvm** - the microVM runtime. Install: `curl -sSL https://smolmachines.com/install.sh | bash`
- **podman or docker** - needed to build the sandbox image and run pi subcommands. podman is preferred (rootless, no daemon).
- **Linux** with KVM (x86_64 or arm64). It also works on **WSL2**, just make sure nested virtualization is enabled (`nestedVirtualization=true` in `.wslconfig`). macOS *should* work, but it's untested - feel free to give it a go and raise a bug report if you run into problems.

## Install

```sh
curl -sSL https://raw.githubusercontent.com/neuroblaze/smol-pi/v1.2.0/install.sh | sh
```

This downloads `smol-pi` and `smol-pi-build` to `~/.local/bin/` and the shipped Dockerfiles (`Dockerfile.pi`, `Dockerfile.computer-use`) to `~/.local/etc/smol-pi/` (if desired, you can override the `~/.local/` prefix with `--prefix <dir>`).

Installs pinned to older tags (`v1.2.0` and earlier) predate the computer-use image and only include `Dockerfile.pi`.

To install a different release:

```sh
sh install.sh --version v1.0.1          # specific tag
sh install.sh --version latest          # auto-resolve newest release
sh install.sh --list-versions           # print available release tags
```

## Build the sandbox image

```sh
smol-pi-build
```

This builds the default image (`pi`) using podman (or docker) and exports it as `pi.tar`. The build uses `--no-cache`, so every step re-runs and apt/npm fetch current packages (picking up upstream pi and uv updates). The base image itself is reused if it's already cached locally; `podman pull node:24-trixie-slim` (or `docker pull`) forces a fresh base.

The image is based on `node:24-trixie-slim` and includes:

- The pi coding agent (`@earendil-works/pi-coding-agent`)
- [uv](https://github.com/astral-sh/uv) for Python work
- QoL utilities: curl, ripgrep, jq, git, vim, less, file, make, rsync, ssh, sudo, etc.

### Multiple images

You can build and keep multiple images for different development environments. Images are specified using Dockerfiles. It's strongly recommended that you use one of the shipped Dockerfiles as a base. `smol-pi-build` can be used to get a copy you can work on:

```sh
smol-pi-build --generate-dockerfile    # writes Dockerfile.pi to the working directory
mv Dockerfile.pi Dockerfile.rust       # edit, add rustup/cargo, etc.
smol-pi-build rust                     # builds Dockerfile.rust -> rust.tar
```

The image name is derived from the Dockerfile filename: `Dockerfile.<name>` produces `<name>.tar`, which can be launched with `smol-pi --image <name>`.

```sh
smol-pi-build              # builds Dockerfile.pi -> pi.tar (the default)
smol-pi-build rust         # builds Dockerfile.rust -> rust.tar
smol-pi-build cpp          # builds Dockerfile.cpp  -> cpp.tar
```

Then launch whichever you need:

```sh
smol-pi                    # default (pi.tar)
smol-pi --image rust       # rust.tar
smol-pi --image cpp        # cpp.tar
```

If you want to base your image on the `computer-use` image that includes a framebuffer and x11 server, you can add `computer-use` as an argument to `--generate-dockerfile`:

```sh
smol-pi-build --generate-dockerfile computer-use   # writes Dockerfile.computer-use to the working directory
mv Dockerfile.computer-use Dockerfile.swing        # edit, add JDK/swing, etc.
smol-pi-build swing                                # builds Dockerfile.swing -> swing.tar
```

This works for any Dockerfile placed in the data directory (by default: `~/.local/etc/smol-pi/`), so you can also copy your own Dockerfiles there as templates. For example, if you create a Dockerfile called `Dockerfile.electron-dev` and place it in the data directory, you can then have smol-pi-build create a copy:

```sh
smol-pi-build --generate-dockerfile electron-dev   # writes Dockerfile.electron-dev to the working directory
```

Generated images are .tar files which are placed in the data directory (default `~/.local/etc/smol-pi/`).

### Computer use (virtual desktop)

`Dockerfile.computer-use` builds an optional image with a headless desktop so agents can work with GUI apps and web UIs:

```sh
smol-pi-build computer-use          # builds computer-use.tar
smol-pi --image computer-use --vnc  # boot with VNC access to the desktop
```

The image contains Xvfb (1920x1080x24 virtual display), openbox (EWMH window manager), a D-Bus session bus with AT-SPI2 accessibility, x11vnc, and Chromium. It's compatible with the [`pi-computer-use`](https://github.com/injaneity/pi-computer-use) extension, which drives X11 apps via AT-SPI/EWMH and can use Chromium over CDP:

```sh
smol-pi install npm:@injaneity/pi-computer-use   # installs the extension into ~/.pi
smol-pi --image computer-use --vnc -p "open a browser and ..."
```

Notes:

- **VNC** (`--vnc`) can be used to view the virtual desktop; connect to `vnc://localhost:5900`. `--vnc-port <port>` changes the host port. VNC is bound to localhost on the host only, and does nothing on images without a desktop (like the default `pi`).
- **Extra ports**: `--port <host:guest>` publishes any guest port to localhost, e.g. `--port 5173:5173` to open a dev server in your own browser while the agent works in Chromium.
- **Memory**: browser work benefits from more RAM; using `--mem 4096` is recommended.
- **Display size**: override the default geometry on the host, e.g. `SMOL_PI_DESKTOP_GEOMETRY=2560x1440x24 smol-pi --image computer-use`.
- Desktop daemon logs live at `/tmp/smol-pi-desktop.log` inside the guest.

## Run

```sh
smol-pi                    # drop into pi interactively (default image)
smol-pi -p "fix the bug"   # run pi with a prompt
smol-pi --shell            # drop into a plain shell instead of pi
smol-pi --image rust       # launch a different image (rust.tar)
```

Your current working directory is mounted at `/workspace`. `~/.pi` is mounted at `/root/.pi` read-write (so pi can persist config/auth across runs). Everything else inside the VM is ephemeral.

## Pi subcommands

Pi has subcommands that only manage the `~/.pi` directory — they don't invoke the agent and don't need a full VM:

```sh
smol-pi install <package>   # install a pi extension
smol-pi remove <package>    # remove an extension
smol-pi update --extensions # update extensions
smol-pi list                # list installed extensions
smol-pi config              # open the resource configuration TUI
```

These run via podman or docker directly (no VM boot), so they're nearly instant. The `~/.pi` directory and current working directory are mounted into the container. With docker, the container runs as your host UID to avoid creating root-owned files in `~/.pi`.

Note that updating pi itself has no lasting effect: `smol-pi update` runs in a disposable container, so the updated binary is discarded when it exits (pi is baked into the image — rebuild with `smol-pi-build` to update it). `smol-pi update --extensions` *does* work and is the recommended way to update extensions, since extensions live in `~/.pi` on the host.

### Installing pi extensions

Pi extensions (via `pi install`) are stored in `~/.pi/agent/`, which is a bind mount from the host. Therefore, installing extensions in the Dockerfile won't work; they'll be shadowed by the mount at runtime. Install extensions after the image is built instead:

```sh
smol-pi install @anthropic/plan-mode
```

This runs via podman/docker (no VM boot) and writes directly to `~/.pi` on the host, where the VM will pick it up on the next run.

## Network modes

```sh
smol-pi --network-mode block-local    # default: internet allowed, private networks blocked
smol-pi --network-mode block-all      # all egress blocked
smol-pi --network-mode block-internet # private networks allowed, internet blocked
smol-pi --network-mode allow-all      # everything allowed
```

| Mode | Public internet | Private networks | DNS | Use case |
|------|-----------------|-------------------|-----|----------|
| `block-local` (default) | allowed | blocked | forced to Cloudflare DNS | General use — agent can reach APIs but not your LAN |
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

By default, `block-local` forces 1.1.1.1 (the system DNS is typically at your LAN gateway, which is a blocked private IP). On IPv6-only hosts, Cloudflare's IPv6 resolver (`2606:4700:4700::1111`) is used instead, since 1.1.1.1 is unreachable without an IPv4 route. All other modes use the system DNS that smolvm injects at boot, so internal hostnames resolve. Use `--dns` to override in any mode.

## Options

```
smol-pi                       Drop into pi interactively (default image)
smol-pi <pi-args>              Run pi with args (e.g. smol-pi -p "fix the bug")
smol-pi --shell                Drop into a plain shell (/bin/sh) instead of pi
smol-pi --image <name>         Launch image <name>.tar (default: pi)
smol-pi --config <path>        Load a config file (default: ~/.local/etc/smol-pi/config)
smol-pi --pi-dir <path>        Use an alternate .pi directory (default: ~/.pi)
smol-pi --network-mode <mode>  Set network egress mode (default: block-local)
smol-pi --allow-host <host>    Allow egress to a specific host (block-all only)
smol-pi --ssh-agent            Forward host SSH agent into the guest (git/ssh)
smol-pi --dns <server>         Override DNS server (default: mode-dependent)
smol-pi --mem <MiB>            VM memory in MiB (default: 2048)
smol-pi --vnc                  Expose the guest desktop via VNC (desktop images)
smol-pi --vnc-port <port>      Host port for --vnc (default: 5900)
smol-pi --port <host:guest>    Publish a guest port to localhost (repeatable)
smol-pi clean                   Remove stale smolvm cache (frees disk space)
smol-pi --help                  Show this help
```

Memory: 2 GiB default (override with `--mem`; elastic via virtio-balloon).

## SSH agent forwarding

`--ssh-agent` forwards the host's SSH agent socket into the guest so `git`/`ssh` work inside the sandbox without ever exposing key files to it (protocol-level forwarding via smolvm — private key material never crosses the VM boundary, the guest can only request signatures). Off by default; enable via `--ssh-agent` or `SSH_AGENT=1` in a config file.

```sh
smol-pi --ssh-agent
```

smolvm forwards whatever `SSH_AUTH_SOCK` the calling shell has set — it isn't aware of specific agent implementations. On macOS, a plain terminal's ambient `SSH_AUTH_SOCK` is usually the default `launchd` agent (no identities loaded), since tools like 1Password route through `ssh_config`'s `IdentityAgent` rather than the env var. If you use 1Password's SSH agent (or similar), export `SSH_AUTH_SOCK` to point at its actual socket before running `smol-pi --ssh-agent`.

## Config file

A config file lets you set default values for smol-pi flags without typing them every time. The default config file is `~/.local/etc/smol-pi/config`; override with `--config <path>` (useful for per-scenario configs).

Format is shell variables (`KEY=VALUE`, one per line). CLI flags always take precedence over config-file values.

```sh
# ~/.local/etc/smol-pi/config — default config
IMAGE=rust
NETWORK_MODE=block-all
ALLOW_HOSTS=api.anthropic.com api.openai.com
MEM=4096
DNS=1.1.1.1
# PI_DIR=~/.pi   # (default)
```

Recognised keys:

| Key | Maps to | Example |
|------|---------|---------|
| `IMAGE` | `--image` | `IMAGE=rust` |
| `PI_DIR` | `--pi-dir` | `PI_DIR=~/.pi` |
| `NETWORK_MODE` | `--network-mode` | `NETWORK_MODE=block-all` |
| `ALLOW_HOSTS` | `--allow-host` (space-separated) | `ALLOW_HOSTS=api.anthropic.com api.openai.com` |
| `DNS` | `--dns` | `DNS=1.1.1.1` |
| `MEM` | `--mem` | `MEM=4096` |
| `SSH_AGENT` | `--ssh-agent` | `SSH_AGENT=1` |
| `VNC` | `--vnc` | `VNC=1` |
| `VNC_PORT` | `--vnc-port` | `VNC_PORT=5900` |
| `PORTS` | `--port` (space-separated) | `PORTS=5173:5173 8080:80` |

Per-scenario configs:

```sh
smol-pi --config ~/.local/etc/smol-pi/rust.conf
smol-pi --config ~/.local/etc/smol-pi/locked-down.conf
```

## Disk cleanup

smolvm >= 1.3.1 cleans up ephemeral VM state automatically on graceful exit ([smolvm#497](https://github.com/smol-machines/smolvm/pull/497)). Earlier versions leaked ~1.4 GB of VM state (qcow2 disks, logs) per `machine run` into `~/.cache/smolvm/vms/`, and image archives accumulate in `~/.cache/smolvm-image-archives/` across builds.

smol-pi keeps a safety net for the cases smolvm can't handle itself:

- **Orphaned processes**: if smol-pi is `SIGKILL`'d (OOM killer, `kill -9`), the smolvm process can't run its cleanup. The next `smol-pi` run detects and kills any orphaned `smolvm-bin` using the same image before booting.
- **`smol-pi-build`**: orphaned image archives from previous builds are removed after a rebuild (applies on any smolvm version).
- **`smol-pi clean`**: manual reclamation of stale VM dirs and orphaned image archives, for crash recovery or smolvm < 1.3.1.

```sh
smol-pi clean
```

This removes all stale VM dirs and any image archives that don't correspond to a `.tar` currently in the data directory, so every built image keeps its archive.

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
| `smol-pi-build` | Image builder — podman/docker, `--no-cache`, builds `Dockerfile.<name>` |
| `Dockerfile.pi` | Default image definition — node:24-trixie-slim + pi + uv + QoL utils |
| `Dockerfile.computer-use` | Optional desktop image — Xvfb + openbox + AT-SPI2 + x11vnc + Chromium |
| `install.sh` | One-line installer — downloads scripts, checks prereqs |
| `scripts/compute_cidrs.py` | CIDR allowlist generator with sanity checks |

## License

MIT-0 (public domain equivalent). See [LICENSE](LICENSE).

Copyright (c) 2026 Peter Kazakoff
