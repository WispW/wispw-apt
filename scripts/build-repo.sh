#!/usr/bin/env bash
# Build the WispW APT repository from GitHub Releases.
#
# Release contract is documented in README.md.
# Runs on the GitHub Actions Ubuntu runner; local runs need gh, jq,
# dpkg-deb, apt-ftparchive, gpg, gpgv, gzip and sha256sum.

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)

target_repo=${TARGET_REPO:-${GITHUB_REPOSITORY:-WispW/wispw-apt}}
output_dir=${OUTPUT_DIR:-$root/public}
suite=${SUITE:-stable}
component=${COMPONENT:-main}
arch=${ARCH:-all}
origin=${ORIGIN:-WispW}
label=${LABEL:-WispW APT}

die() {
    printf 'build-repo: %s\n' "$1" >&2
    exit 1
}

for cmd in gh jq dpkg-deb apt-ftparchive gpg gpgv gzip awk sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

[[ $target_repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
    die "invalid TARGET_REPO: $target_repo"

case $output_dir in
    /*) ;;
    *) output_dir="$root/$output_dir" ;;
esac

[[ $output_dir != "/" && $output_dir != "$root" ]] || \
    die "refusing to clean unsafe output directory: $output_dir"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

pool="$workdir/pool"
raw_packages="$workdir/Packages.raw"
packages="$workdir/Packages"
filename_map="$workdir/filename-map.tsv"

rm -rf "$output_dir"
mkdir -p "$pool" "$output_dir/dists/$suite/$component/binary-$arch"

if [[ -n ${APT_GPG_KEY_ID:-} ]]; then
    key_id=$APT_GPG_KEY_ID
else
    key_id=$(gpg --batch --list-secret-keys --with-colons 2>/dev/null | \
        awk -F: '$1 == "fpr" { print $10; exit }')
fi
[[ $key_id ]] || die "no secret GPG key found (import one first)"

gpg_args=(--batch --yes --local-user "$key_id")
if [[ -n ${APT_GPG_PASSPHRASE:-} ]]; then
    gpg_args+=(--pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE")
fi

releases=$(gh release list \
    --repo "$target_repo" \
    --limit 1000 \
    --json tagName,isDraft,isPrerelease)

mapfile -t tags < <(jq -r '
    .[]
    | select(.isDraft == false)
    | select(.isPrerelease == false)
    | .tagName
' <<< "$releases")

(( ${#tags[@]} > 0 )) || die "no published releases in $target_repo"

for tag in "${tags[@]}"; do
    [[ $tag =~ ^[A-Za-z0-9._+-]+$ ]] || die "unsupported tag characters: $tag"

    release=$(gh release view "$tag" --repo "$target_repo" --json body,assets)

    mapfile -t deb_assets < <(jq -r '
        .assets[]
        | select(.name | endswith(".deb"))
        | .name
    ' <<< "$release")

    if (( ${#deb_assets[@]} != 1 )); then
        die "$tag: expected exactly one .deb asset, found ${#deb_assets[@]}"
    fi

    asset=${deb_assets[0]}
    [[ $asset =~ ^[A-Za-z0-9._+-]+\.deb$ ]] || \
        die "$tag: unsupported asset name: $asset"

    mkdir -p "$pool/$tag"
    gh release download "$tag" \
        --repo "$target_repo" \
        --pattern "$asset" \
        --dir "$pool/$tag"

    deb="$pool/$tag/$asset"
    [[ -f $deb ]] || die "$tag: asset was not downloaded: $asset"

    package=$(dpkg-deb -f "$deb" Package)
    version=$(dpkg-deb -f "$deb" Version)
    deb_arch=$(dpkg-deb -f "$deb" Architecture)

    [[ $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || \
        die "$tag: invalid Package: $package"
    [[ $version =~ ^[A-Za-z0-9.+:~-]+$ ]] || \
        die "$tag: invalid Version: $version"
    [[ $deb_arch == "$arch" ]] || \
        die "$tag: expected Architecture $arch, got $deb_arch"
    [[ $asset == "$package.deb" ]] || \
        die "$tag: asset must be $package.deb, got $asset"

    expected_tag="${package}-v${version}"
    [[ $tag == "$expected_tag" ]] || \
        die "$tag: tag must be $expected_tag"

    body=$(jq -r '.body // ""' <<< "$release")
    body_package=$(printf '%s\n' "$body" | \
        sed -n 's/^Package:[[:space:]]*//p' | head -n1 | tr -d '\r')
    body_version=$(printf '%s\n' "$body" | \
        sed -n 's/^Version:[[:space:]]*//p' | head -n1 | tr -d '\r')
    body_sha=$(printf '%s\n' "$body" | \
        sed -n 's/^SHA256:[[:space:]]*//p' | head -n1 | \
        tr -d ' \r' | tr 'A-F' 'a-f')

    [[ $body_package == "$package" ]] || \
        die "$tag: release body Package does not match .deb control"
    [[ $body_version == "$version" ]] || \
        die "$tag: release body Version does not match .deb control"
    [[ $body_sha ]] || die "$tag: release body is missing SHA256"

    actual_sha=$(sha256sum "$deb" | awk '{print $1}')
    [[ $body_sha == "$actual_sha" ]] || \
        die "$tag: release body SHA256 does not match .deb"

    release_url="https://github.com/$target_repo/releases/download/$tag/$asset"
    printf '%s\t%s\n' "./$tag/$asset" "$release_url" >> "$filename_map"

    printf 'validated %s (%s %s %s)\n' "$tag" "$package" "$version" "$deb_arch"
done

(cd "$pool" && apt-ftparchive packages .) > "$raw_packages"
[[ -s $raw_packages ]] || die "apt-ftparchive produced an empty Packages file"

awk -F '\t' '
    NR == FNR { urls[$1] = $2; next }
    /^Filename: / {
        path = substr($0, 11)
        if (!(path in urls)) {
            printf "build-repo: no release URL for %s\n", path > "/dev/stderr"
            exit 1
        }
        print "Filename: " urls[path]
        next
    }
    { print }
' "$filename_map" "$raw_packages" > "$packages"

install -m 0644 "$packages" \
    "$output_dir/dists/$suite/$component/binary-$arch/Packages"
gzip -9 -n -c "$packages" > \
    "$output_dir/dists/$suite/$component/binary-$arch/Packages.gz"

apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=$origin" \
    -o "APT::FTPArchive::Release::Label=$label" \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o "APT::FTPArchive::Release::Architectures=$arch" \
    -o "APT::FTPArchive::Release::Components=$component" \
    -o "APT::FTPArchive::Release::Description=$label" \
    release "$output_dir/dists/$suite" > "$output_dir/dists/$suite/Release"

gpg "${gpg_args[@]}" \
    --clearsign \
    --output "$output_dir/dists/$suite/InRelease" \
    "$output_dir/dists/$suite/Release"

gpg "${gpg_args[@]}" \
    --detach-sign --armor \
    --output "$output_dir/dists/$suite/Release.gpg" \
    "$output_dir/dists/$suite/Release"

gpgv --keyring "$root/keyring/wispw-archive-keyring.gpg" \
    "$output_dir/dists/$suite/InRelease" >/dev/null

install -m 0644 "$root/keyring/wispw-archive-keyring.gpg" "$output_dir/"
if [[ -f "$root/keyring/wispw-archive-keyring.asc" ]]; then
    install -m 0644 "$root/keyring/wispw-archive-keyring.asc" "$output_dir/"
fi

cat > "$output_dir/index.html" <<'EOF'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>WispW APT Repository</title>
</head>
<body>
  <h1>WispW APT Repository</h1>
  <p>第三方 Debian/Ubuntu 软件源，不是官方仓库。</p>
  <pre><code>sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://repo.wennie99s.top/wispw-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/wispw.gpg &gt;/dev/null

echo "deb [signed-by=/etc/apt/keyrings/wispw.gpg] https://repo.wennie99s.top stable main" \
  | sudo tee /etc/apt/sources.list.d/wispw.list

sudo apt update
sudo apt install hostnamefetch</code></pre>
</body>
</html>
EOF

printf 'repository generated at %s\n' "$output_dir"
printf 'suite=%s component=%s arch=%s\n' "$suite" "$component" "$arch"
printf 'packages: %s\n' "$(grep -c '^Package: ' "$packages")"
