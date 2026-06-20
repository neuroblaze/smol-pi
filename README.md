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
- **podman or docker** — only needed to build the sandbox image (not to run it). podman is preferred (rootless, no daemon).
- **Linux** with KVM (x86_64 or arm64). macOS support is expected but untested — see [TODO](TODO.md) item "macOS testing."

## Install

```sh
curl -sSL https://raw.githubusercontent.com/neuroblaze/smol-pi/main/install.sh | sh
```

Prefer to read it first?

```sh
curl -sSL -o install.sh https://raw.githubusercontent.com/neuroblaze/smol-pi/main/install.sh
less install.sh
sh install.sh
```

This downloads `smol-pi`, `smol-pi-build`, and `Dockerfile.pi` to `~/.local/bin/` (override with `--prefix <dir>`).

## Build the sandbox image

```sh
smol-pi-build
```

This builds the `pi-sandbox` container image using podman (or docker) and exports it as `pi-sandbox.tar`. The build uses `--no-cache`, so re-running it always pulls fresh base images and picks up upstream updates to pi, uv, and the base OS.

The image is based on `node:24-trixie-slim` and includes:

- The pi coding agent (`@earendil-works/pi-coding-agent`)
- [uv](https://github.com/astral-sh/uv) for Python work
- QoL utilities: curl, ripgrep, jq, git, vim, less, file, make, rsync, ssh, sudo, etc.

## Run

```sh
smol-pi                    # drop into pi interactively
smol-pi -p "fix the bug"   # run pi with a prompt
smol-pi --shell            # drop into a plain shell instead of pi
```

Your current working directory is mounted at `/workspace`. `~/.pi` is mounted at `/root/.pi` read-write (so pi can persist config/auth across runs). Everything else inside the VM is ephemeral.

## Network modes

```sh
smol-pi --network-mode block-local    # default: internet allowed, private networks blocked
smol-pi --network-mode block-all      # all egress blocked
smol-pi --network-mode block-internet # private networks allowed, internet blocked
smol-pi --network-mode allow-all      # everything allowed
```

| Mode | Public internet | Private networks | DNS | Use case |
|------|-----------------|-------------------|-----|----------|
| `block-local` (default) | allowed | blocked | forced to 9.9.9.9 | General use — agent can reach APIs but not your LAN |
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

By default, `block-local` forces 9.9.9.9 (the system DNS is typically at your LAN gateway, which is a blocked private IP). All other modes use the system DNS that smolvm injects at boot, so internal hostnames resolve. Use `--dns` to override in any mode.

## Options

```
smol-pi                       Drop into pi interactively
smol-pi <pi-args>              Run pi with args (e.g. smol-pi -p "fix the bug")
smol-pi --shell                Drop into a plain shell (/bin/sh) instead of pi
smol-pi --pi-dir <path>        Use an alternate .pi directory (default: ~/.pi)
smol-pi --network-mode <mode>  Set network egress mode (default: block-local)
smol-pi --allow-host <host>    Allow egress to a specific host (block-all only)
smol-pi --dns <server>         Override DNS server (default: mode-dependent)
smol-pi --help                  Show this help
```

Memory: 4 GiB (elastic via virtio-balloon).

## How it works

1. `smol-pi-build` creates an OCI image (`pi-sandbox.tar`) containing the pi agent and a custom entrypoint (`smol-pi-entrypoint`) that handles DNS configuration based on a `SMOL_PI_DNS` env var.
2. `smol-pi` invokes `smolvm machine run` with the image, your project mounted at `/workspace`, `~/.pi` mounted at `/root/.pi`, and network flags corresponding to the chosen mode.
3. smolvm boots a real Linux kernel in a microVM (KVM on Linux, Hypervisor.framework on macOS), with network egress filtered by a userspace proxy (passt).
4. When the command exits, the VM is destroyed. Only the mounted directories persist.

## Files

| File | Description |
|------|-------------|
| `smol-pi` | Launcher script — boots the VM with network/DNS config |
| `smol-pi-build` | Image builder — podman/docker, `--no-cache`, embeds the Dockerfile |
| `Dockerfile.pi` | Image definition — node:24-trixie-slim + pi + uv + QoL utils |
| `install.sh` | One-line installer — downloads scripts, checks prereqs |
| `scripts/compute_cidrs.py` | CIDR allowlist generator with sanity checks |
| `TODO` | Improvement ideas and findings |

## Security notes

- `~/.pi` is mounted read-write. This is necessary for pi to persist config and auth across runs, but it means a compromised agent could modify or exfiltrate pi's credentials. The `block-all` mode mitigates network exfiltration. A `--secret-env` / `--secret-file` passthrough is planned (see [TODO](TODO)).
- The VM uses its own kernel, so the agent cannot access host kernel features or devices. Network egress is the main attack surface, which is why the default mode blocks private networks.
- The `--no-cache` build ensures you get fresh base images, but you should still rebuild periodically to pick up security updates in the base OS and pi itself.

## License

MIT