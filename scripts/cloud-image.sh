#!/usr/bin/env bash

set -eux

# external variables that must be set
echo vars: $ARCH

# switch to dist dir
SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
DIST_DIR="${SCRIPT_DIR}/dist/img"
mkdir -p $DIST_DIR

cd $DIST_DIR

download() (
    FILE="debian-${DEBIAN_VERSION}-genericcloud-${1}-daily.qcow2"
    URL="https://cloud.debian.org/images/cloud/${DEBIAN_CODENAME}/daily/latest/${FILE}"
    curl -L -O -C - $URL

    shasum -a 512 "${FILE}" >"${FILE}.sha512sum"
)

# download
download $ARCH

# validate
(
    curl -sL https://cloud.debian.org/images/cloud/${DEBIAN_CODENAME}/daily/latest/SHA512SUMS | grep "genericcloud-${ARCH}-daily\.qcow2$" | shasum -a 512 --check --status
)

echo download successful
ls -lh .
