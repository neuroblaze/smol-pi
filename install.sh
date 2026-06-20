#!/bin/sh
# install.sh — install smol-pi: an ephemeral microVM sandbox for the pi agent.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/neuroblaze/smol-pi/main/install.sh | sh
#
# Or download-and-review:
#   curl -sSL -o install.sh https://raw.githubusercontent.com/neuroblaze/smol-pi/main/install.sh
#   less install.sh
#   sh install.sh
#
# Options:
#   --prefix <dir>    Install to <dir>/bin (default: ~/.local)

set -e

# ---------------------------------------------------------------------------
# ASCII art banner
# ---------------------------------------------------------------------------
print_banner() {
  cat <<'BANNER'
   __  __               __      __
  /_ /___ ____  ____  / /____  / /_  ____  ____
 / __ / _ `/ _ `/ _ `/ __/ _ \/ __ \/ __/ / ___/
/_/ /_/\_,_/\_,_/\_,_/\__/\___/_/ /_/\__/_/

  ephemeral microVM sandbox for the pi agent
  https://github.com/neuroblaze/smol-pi

BANNER
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PREFIX="${HOME}/.local"
BASE_URL="https://raw.githubusercontent.com/neuroblaze/smol-pi/main"
FILES="smol-pi smol-pi-build Dockerfile.pi"

# ---------------------------------------------------------------------------
# Parse options
# ---------------------------------------------------------------------------
usage() {
  cat <<USAGE
Usage: sh install.sh [--prefix <dir>]

  --prefix <dir>    Install scripts to <dir>/bin (default: ~/.local)
  --help            Show this help
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      [ $# -lt 2 ] && { echo "install: --prefix requires an argument" >&2; exit 2; }
      PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      PREFIX="${1#--prefix=}"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "install: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo "install: curl is required but not found on PATH." >&2
  exit 1
fi

# Resolve PREFIX to an absolute path.
case "$PREFIX" in
  /*) ;;
  *)  PREFIX="$(cd ~ && pwd)/$PREFIX" ;;
esac

BINDIR="$PREFIX/bin"

print_banner

echo "==> Installing to $BINDIR"
mkdir -p "$BINDIR"

# ---------------------------------------------------------------------------
# Download files
# ---------------------------------------------------------------------------
for f in $FILES; do
  echo "    downloading $f"
  curl -sSfL "$BASE_URL/$f" -o "$BINDIR/$f"
done

chmod +x "$BINDIR/smol-pi" "$BINDIR/smol-pi-build"

echo "==> Done. Files installed to $BINDIR"

# ---------------------------------------------------------------------------
# Check PATH
# ---------------------------------------------------------------------------
case ":$PATH:" in
  *":$BINDIR:"*)
    ;;
  *)
    echo
    echo "WARNING: $BINDIR is not in your PATH."
    echo "  Add it by running:"
    echo "    echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.bashrc"
    echo "  (or the equivalent for your shell's config file)"
    echo "  Then start a new shell or run: export PATH=\"$BINDIR:\$PATH\""
    ;;
esac

# ---------------------------------------------------------------------------
# Check for smolvm
# ---------------------------------------------------------------------------
echo
if command -v smolvm >/dev/null 2>&1; then
  echo "smolvm:  found ($(smolvm --version 2>/dev/null || echo 'unknown version'))"
else
  echo "smolvm:  NOT FOUND"
  echo
  echo "  smol-pi requires smolvm to boot the microVM."
  echo "  Install it with:"
  echo "    curl -sSL https://smolmachines.com/install.sh | bash"
  echo
  echo "  Then re-run this installer (or just run smol-pi-build directly)."
fi

# ---------------------------------------------------------------------------
# Check for container build tool
# ---------------------------------------------------------------------------
echo
if command -v podman >/dev/null 2>&1; then
  echo "podman:  found"
elif command -v docker >/dev/null 2>&1; then
  echo "docker:  found"
else
  echo "podman/docker: NOT FOUND"
  echo
  echo "  Building the sandbox image requires podman or docker."
  echo "  Install one of:"
  echo "    podman  (rootless, no daemon) - https://podman.io/docs/installation"
  echo "    docker  (requires dockerd)   - https://docs.docker.com/engine/install/"
fi

# ---------------------------------------------------------------------------
# Final instructions
# ---------------------------------------------------------------------------
echo
echo "================================================================"
echo
echo "  Next steps:"
echo
echo "  1. Build the sandbox image (needs podman or docker):"
echo "       smol-pi-build"
echo
echo "  2. Run the sandbox (needs smolvm + the built image):"
echo "       smol-pi"
echo
echo "  Or drop into a plain shell:"
echo "       smol-pi --shell"
echo
echo "  See all options:"
echo "       smol-pi --help"
echo
echo "================================================================"