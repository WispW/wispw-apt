#!/usr/bin/env bash
# Smoke-test a generated APT repository against clean Debian/Ubuntu images.
#
# Usage:
#   scripts/test-repo.sh [public-dir]
#
# Environment:
#   PACKAGE   package to install. Default: hostnamefetch
#   HOST_URL  URL used inside containers. Default: http://127.0.0.1:8000
#   PORT      local HTTP port. Default: 8000
#   IMAGES    space-separated Docker images.

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
public_dir=${1:-$root/public}
package=${PACKAGE:-hostnamefetch}
host_url=${HOST_URL:-http://127.0.0.1:8000}
port=${PORT:-8000}
images=${IMAGES:-"debian:12 debian:13 ubuntu:22.04 ubuntu:24.04 ubuntu:26.04"}

die() {
    printf 'test-repo: %s\n' "$1" >&2
    exit 1
}

[[ -f "$public_dir/dists/stable/InRelease" ]] || die "missing InRelease"
[[ -f "$public_dir/dists/stable/main/binary-all/Packages" ]] || \
    die "missing Packages"
[[ -f "$public_dir/wispw-archive-keyring.gpg" ]] || die "missing public key"

command -v gpgv >/dev/null 2>&1 || die "gpgv is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v docker >/dev/null 2>&1 || die "docker is required"

gpgv --keyring "$root/keyring/wispw-archive-keyring.gpg" \
    "$public_dir/dists/stable/InRelease" >/dev/null

python3 -m http.server "$port" \
    --bind 127.0.0.1 \
    --directory "$public_dir" >/dev/null 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

for image in $images; do
    printf '\n== %s ==\n' "$image"
    docker run --rm \
        --network host \
        -e DEBIAN_FRONTEND=noninteractive \
        -e HOST_URL="$host_url" \
        -e PACKAGE="$package" \
        "$image" \
        bash -c '
            set -eux
            apt-get update -qq
            apt-get install -y -qq --no-install-recommends ca-certificates curl

            install -d -m 0755 /etc/apt/keyrings
            curl -fsSL --retry 5 --retry-delay 1 --retry-connrefused \
                "$HOST_URL/wispw-archive-keyring.gpg" \
                -o /etc/apt/keyrings/wispw.gpg

            printf "deb [signed-by=/etc/apt/keyrings/wispw.gpg] %s stable main\n" \
                "$HOST_URL" > /etc/apt/sources.list.d/wispw.list

            apt-get update -qq
            apt-cache policy "$PACKAGE"
            apt-get install -y -qq --no-install-recommends "$PACKAGE"
            "$PACKAGE" --version
        '
done

printf '\nall repository tests passed\n'
