# smol-pi sandbox: computer-use image

Context for an agent running inside a [smol-pi](https://github.com/neuroblaze/smol-pi) sandbox built from `Dockerfile.computer-use` (the default `pi` image **plus a headless X11 desktop**). Copy this into your project's `AGENTS.md` so a fresh agent starts with this knowledge.

For the parts shared with the default image, this file repeats the essentials; `sample_AGENTS/AGENTS_default.md` has slightly more detail.

## What you are running in

- An **ephemeral micro-VM**, not a container: [smolvm](https://github.com/smol-machines/smolvm) boots a real Linux kernel in a hypervisor via [libkrun](https://github.com/libkrun/libkrun).
- You are **root**, hostname `vm-<random>`. No systemd (PID 1 is the VM init), no Docker/Podman, no `/dev/kvm`.
- Time is UTC. Defaults: **2 GiB RAM** (browser work benefits from more — the user can relaunch with `smol-pi --mem 4096`), a handful of vCPUs, ~20 GB scratch disk.
- When the session ends the VM is destroyed.

## Persistence

Only two host directories are mounted and survive:

- `/workspace` — the user's project directory (your working directory).
- `/root/.pi` — pi's own directory (config, extensions, helpers).

Everything else (`/tmp`, caches, `apt-get` installs, global npm packages) is ephemeral. Put anything you need again under `/workspace` or `~/.pi`. Screenshots and scratch files in `/tmp` are fine.

## OS and installed tooling

Debian 13 (trixie), based on `node:24-trixie-slim`; kernel from libkrunfw.

- **Node.js 24 + npm**, and `pi` itself, installed globally.
- **uv/uvx** for Python — no system Python/pip and no C/C++ toolchain (`gcc`/`cc`/`cmake` absent; `make` present).
- git, openssh-client, curl (no wget), rsync, jq, vim, less, file, tar, unzip, xz, zstd, ripgrep (`rg`), `fd`, procps, sudo (redundant), gnupg, iproute2.

## The virtual desktop

The image starts a headless desktop before pi launches, and every process inherits it:

- **Xvfb** at `DISPLAY=:99`, resolution **1920x1080x24** (the user can override at launch with `SMOL_PI_DESKTOP_GEOMETRY=2560x1440x24`).
- **openbox** window manager with full EWMH support (`_NET_ACTIVE_WINDOW`, `_NET_CLIENT_LIST`, ...).
- A D-Bus **session bus** and an **AT-SPI2** accessibility bus, already running (`DBUS_SESSION_BUS_ADDRESS` is exported, `QT_ACCESSIBILITY=1`).
- **x11vnc** serves the display on port 5900 only if the user launched with `smol-pi --vnc` — they can watch the desktop from the host. Nothing to set up here.

Installed for desktop work: **Chromium**, `scrot`, `xclip`, `xterm`, `zenity`, `xwininfo`, `xprop`, `at-spi2-core`. There is **no `xdotool`**.

Chromium refuses to run as root without flags, so `/usr/local/bin/chromium` is a wrapper that adds `--no-sandbox --disable-dev-shm-usage`. Use `chromium` from `PATH` (the wrapper); the sandbox boundary is the VM itself. The `launch_browser` tool of pi-computer-use picks this wrapper up automatically.

## Networking

smolvm virtualizes networking in user space; it does not behave like a normal NIC.

- **Filtered modes** (`block-local` default, `block-internet`, `block-all`): a private virtio-net link (`eth0`, e.g. `100.96.0.2/30`), filtered on the host. `block-local` allows the public internet but blocks private/LAN ranges and cloud metadata.
- **`allow-all` mode**: libkrun **TSI** — sockets are proxied to the host, there is no real interface (`lo` plus a meaningless `dummy0` with a `203.0.113.x` address, no default route), but outbound TCP/UDP works.

```sh
grep -q tsi_hijack /proc/cmdline && echo TSI || echo virtio-net
```

- **Don't use `ping` to test connectivity** (ICMP is dropped or unsupported). Use `curl` or a TCP connect.
- **Nothing can connect to you** unless the user published a port (`--port`, or `--vnc` for 5900). Forwarded connections arrive at a **non-loopback address**, so bind servers to `0.0.0.0`, not `127.0.0.1`.
- Outbound traffic is NAT'd through the host, and smol-pi rewrites `/etc/resolv.conf`. Don't "fix" the resolver; ask the user if it looks wrong.
- If a destination is blocked (LAN host, non-web port), ask the user — network mode is a host-side launch flag.

## Driving the desktop with pi-computer-use

The `pi-computer-use` extension (if installed) exposes an accessibility-first toolset: it walks the AT-SPI2 tree (`find_roots`, `observe_ui`, `search_ui`, `inspect_ui`, `read_text`), enriches it with EWMH window state, captures pixels from the X server (`scrot`, visual observe), and injects input through XTEST (`act_ui`).

Environment-specific hints:

- **`xterm` has no AT-SPI support**, so it is invisible to `find_roots`/`observe_ui` even though it is on screen. For tool-driven GUI work prefer Chromium, `zenity`, or other GTK apps; screenshots still capture everything.
- Browser pages opened with `launch_browser` / `navigate_browser` are driven over **CDP**, not XTEST, so the input caveats below do not apply inside them.
- Repeat the target `ref` on every action in a batch, and re-observe after actions that change the UI: state ids go stale and the validator rejects some combinations (e.g. a `keypress` without `ref`).
- Input goes to the active/foreground window; if an action is refused with a foreground/occlusion error, click or activate the window first.

## Input workarounds (pi-computer-use)

As of pi-computer-use **0.5.1**, the native Linux helper cannot type **unshifted punctuation** with `typeText`/`setText`. These characters fail:

```
`  -  =  [  ]  \  ;  '  ,  .  /
```

The error is `Unsupported XTEST character '<c>'`, and typing stops at the first bad character, so partial text may land (e.g. `https:` before the first `/`). Letters, digits, spaces, uppercase, and all *shifted* symbols (`! @ # $ % ^ & * ( ) _ + { } | : " < > ? ~`) type normally — only the characters above need a workaround.

**Try `typeText` first — newer versions may already have fixed this.** If you see the error, fall back to one of these (both verified in this image):

1. **Single-character `keypress`** — send the offending character as its own keypress action, e.g. `act_ui` with `keypress` and `keys: ["."]`. This works for the unshifted characters above. (`keypress` sends the key without Shift, so it is not a substitute for the shifted symbols, which `typeText` already handles.)
2. **Clipboard paste** — works for any text. From the shell, put the text on the X clipboard, then paste into the focused field with `act_ui` `keypress ["ctrl","a"]` (replace existing content) followed by `keypress ["ctrl","v"]`:

   ```sh
   printf '%s' 'https://example.com' | xclip -selection clipboard
   ```

If typing appears to go to the wrong window, activate the target first. After typing, read the field back with `read_text` before assuming success.
