#!/bin/sh
# install.sh — install smol-pi: an ephemeral microVM sandbox for the pi agent.
#
# By default this installs the release tagged with VERSION below. Use
# --version <tag> to install a specific release (e.g. --version v1.0.0)
# or --version latest to auto-resolve the newest release via the GitHub API.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/neuroblaze/smol-pi/v1.0.1/install.sh | sh
#
# Or download-and-review:
#   curl -sSL -o install.sh https://raw.githubusercontent.com/neuroblaze/smol-pi/v1.0.1/install.sh
#   less install.sh
#   sh install.sh
#
# Options:
#   --prefix <dir>       Install to <dir>/bin and <dir>/etc (default: ~/.local)
#   --version <tag>      Release tag to install (default: v1.0.1; or "latest")
#   --list-versions      Print available release tags and exit

set -e

# ---------------------------------------------------------------------------
# ASCII art banner
# ---------------------------------------------------------------------------
print_banner() {
  cat <<'BANNER'
  ███████╗███╗   ███╗ ██████╗ ██╗      ██████╗ ██╗
  ██╔════╝████╗ ████║██╔═══██╗██║      ██╔══██╗██║
  ███████╗██╔████╔██║██║   ██║██║█████╗██████╔╝██║
  ╚════██║██║╚██╔╝██║██║   ██║██║╚════╝██╔═══╝ ██║
  ███████║██║ ╚═╝ ██║╚██████╔╝███████╗ ██║     ██║
  ╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝ ╚═╝     ╚═╝

  ephemeral microVM sandbox for the pi agent
  https://github.com/neuroblaze/smol-pi

BANNER
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
# The release tag this installer ships from. Bumped on each release; the
# README install command references the same tag in its URL.
VERSION="v1.0.1"
REPO="neuroblaze/smol-pi"
PREFIX="${HOME}/.local"
# Executables go to $BINDIR (on PATH); data files go to $ETCDIR.
BIN_FILES="smol-pi smol-pi-build"
ETC_FILES="Dockerfile.pi"

# ---------------------------------------------------------------------------
# Parse options
# ---------------------------------------------------------------------------
usage() {
  cat <<USAGE
Usage: sh install.sh [--prefix <dir>] [--version <tag>] [--list-versions]

  --prefix <dir>       Install executables to <dir>/bin and data files to
                       <dir>/etc/smol-pi (default: ~/.local)
  --version <tag>      Release tag to install (default: $VERSION).
                       Use "latest" to auto-resolve the newest release.
  --list-versions      Print available release tags and exit
  --help               Show this help
USAGE
  exit 0
}

LIST_ONLY=0

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
    --version)
      [ $# -lt 2 ] && { echo "install: --version requires an argument" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${1#--version=}"
      shift
      ;;
    --list-versions)
      LIST_ONLY=1
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

# ---------------------------------------------------------------------------
# Resolve the release tag to install.
#
# --version accepts:
#   - a concrete tag (e.g. v1.0.1)  -> used as-is
#   - "latest"                      -> resolved via the GitHub API to the
#                                      newest published release tag
# The default ($VERSION at the top of this file) is a concrete tag, so the
# common path needs no API call and works offline against raw.githubusercontent.
# ---------------------------------------------------------------------------
resolve_version() {
  # $1 = requested version spec; echoes the resolved tag.
  req="$1"
  if [ "$req" = "latest" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "install: --version latest needs curl to query the GitHub API" >&2
      exit 1
    fi
    # GitHub's /releases endpoint returns JSON; we only need the tag_name of
    # the first (newest) entry. jq is not assumed, so use sed/tr to extract it.
    resp=$(curl -sSfL \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/releases?per_page=1" 2>/dev/null) \
      || { echo "install: failed to query latest release from GitHub" >&2; exit 1; }
    tag=$(printf '%s\n' "$resp" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1)
    if [ -z "$tag" ]; then
      echo "install: could not parse latest release tag from GitHub response" >&2
      exit 1
    fi
    echo "$tag"
  else
    # Normalise: a bare "1.0.1" becomes "v1.0.1".
    case "$req" in
      v*) echo "$req" ;;
      *)  echo "v$req" ;;
    esac
  fi
}

if [ "$LIST_ONLY" -eq 1 ]; then
  echo "Available releases for $REPO:"
  curl -sSfL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/  \1/p' \
    || { echo "install: failed to list releases from GitHub" >&2; exit 1; }
  exit 0
fi

RESOLVED_VERSION=$(resolve_version "$VERSION")

# Resolve PREFIX to an absolute path.
case "$PREFIX" in
  /*) ;;
  *)  PREFIX="$(cd ~ && pwd)/$PREFIX" ;;
esac

BINDIR="$PREFIX/bin"
ETCDIR="$PREFIX/etc/smol-pi"

# raw.githubusercontent.com serves files from a git ref (branch or tag).
# Tagged-release artifacts are immutable, so installs are reproducible.
BASE_URL="https://raw.githubusercontent.com/$REPO/$RESOLVED_VERSION"

print_banner

echo "==> Installing smol-pi $RESOLVED_VERSION"
if [ "$RESOLVED_VERSION" != "$VERSION" ]; then
  echo "    (resolved from $VERSION)"
fi
echo "==> Installing executables to $BINDIR"
echo "==> Installing data files to $ETCDIR"
mkdir -p "$BINDIR" "$ETCDIR"

# ---------------------------------------------------------------------------
# Download files
# ---------------------------------------------------------------------------
for f in $BIN_FILES; do
  echo "    downloading $f"
  curl -sSfL "$BASE_URL/$f" -o "$BINDIR/$f"
done

for f in $ETC_FILES; do
  echo "    downloading $f"
  curl -sSfL "$BASE_URL/$f" -o "$ETCDIR/$f"
done

chmod +x "$BINDIR/smol-pi" "$BINDIR/smol-pi-build"

echo "==> Done."

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