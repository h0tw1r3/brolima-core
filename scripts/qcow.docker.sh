#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH $DEBIAN_VERSION $DOCKER_VERSION $RUNTIME

# computed variables
SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")

# dependencies in case of cross-arch
docker run --privileged --rm tonistiigi/binfmt --install $BINFMT_ARCH

# build qcow image
docker run --rm -t --privileged \
    --platform linux/$ARCH \
    --volume $SCRIPT_DIR:/build \
    --env ARCH \
    --env BINFMT_ARCH \
    --env DEBIAN_VERSION \
    --env DOCKER_VERSION \
    --env RUNTIME \
    debian:${DEBIAN_VERSION} /build/scripts/qcow.sh
