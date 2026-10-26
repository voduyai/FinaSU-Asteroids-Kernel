#!/usr/bin/env bash
# Install the packages scripts/build.sh needs (Debian / Ubuntu, incl. WSL).
# Run with sudo, or as root.
set -euo pipefail

PACKAGES="bc bison flex cpio libssl-dev libelf-dev dwarves zip git curl python3 make"

if ! command -v apt-get > /dev/null; then
    echo "This script uses apt-get. Install these packages with your distribution's tool:" >&2
    echo "  $PACKAGES" >&2
    exit 1
fi
apt-get update -qq
# shellcheck disable=SC2086
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PACKAGES
