#!/bin/sh
# Installs the pinned pixi into $PIXI_HOME/bin (default ~/.pixi/bin) on Linux and macOS.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pin="$here/pixi-release.txt"
dest="${PIXI_HOME:-$HOME/.pixi}/bin"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) want=linux-64 ;;
  Linux/aarch64 | Linux/arm64) want=linux-aarch64 ;;
  Darwin/arm64) want=osx-arm64 ;;
  Darwin/x86_64) want=osx-64 ;;
  *) echo "no bootstrap row for $(uname -s)/$(uname -m); add one to pixi-release.txt" >&2; exit 1 ;;
esac

version=$(awk '$1=="version"{print $2}' "$pin")
source_url=$(awk '$1=="source"{print $2}' "$pin")
set -- $(awk -v p="$want" '$1=="platform" && $2==p {print $3, $4, $5}' "$pin")
[ $# -eq 3 ] || { echo "pixi-release.txt has no complete row for $want" >&2; exit 1; }
asset=$1 sha=$2 member=$3

if [ -x "$dest/pixi" ] && "$dest/pixi" --version 2>/dev/null | grep -qx "pixi $version"; then
  echo "pixi $version already at $dest/pixi"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/$asset" "$source_url$asset"

if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$work/$asset" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)
fi
[ "$got" = "$sha" ] || { echo "checksum mismatch for $asset: got $got, pinned $sha" >&2; exit 1; }

tar -xzf "$work/$asset" -C "$work" "$member"
mkdir -p "$dest"
mv "$work/$member" "$dest/pixi"
chmod +x "$dest/pixi"
echo "pixi $version installed to $dest/pixi; put $dest on PATH"
