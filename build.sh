#!/bin/sh
# Build the pi-sandbox image and export it as a tar for smolvm to boot.
set -e

cd "$(dirname "$0")"

IMAGE_TAG="pi-sandbox"
TARBALL="pi-sandbox.tar"

echo "==> Building $IMAGE_TAG"
docker build -t "$IMAGE_TAG" -f Dockerfile.pi .

echo "==> Exporting to $TARBALL"
docker save "$IMAGE_TAG" -o "$TARBALL"

echo "==> Done. Run with: ./smol-pi"