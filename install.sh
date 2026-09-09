#!/bin/sh
# Installs the pinned repo launcher and the pinned pixi into ~/.local/bin and
# ~/.pixi/bin on Linux and macOS. Run it after `repo init`, from any directory.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pins="$here/bootstrap-pins.txt"
bin="${LOCAL_BIN:-$HOME/.local/bin}"
pixi_bin="${PIXI_HOME:-$HOME/.pixi}/bin"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# repo first. The pins live in the manifest repository, which only exists once
# repo has fetched it, so the launcher that did the fetching is checked here
# against the pin rather than before it -- the one link no pin can cover.
repo_version=$(awk '$1=="repo" && $2=="version"{print $3}' "$pins")
repo_source=$(awk '$1=="repo" && $2=="source"{print $3}' "$pins")
repo_sha=$(awk '$1=="repo" && $2=="sha256"{print $3}' "$pins")
curl -fsSL -o "$work/repo" "$repo_source"
got=$(sha_of "$work/repo")
[ "$got" = "$repo_sha" ] || { echo "checksum mismatch for the repo launcher: got $got, pinned $repo_sha" >&2; exit 1; }

existing=$(command -v repo || true)
if [ -n "$existing" ] && [ "$(sha_of "$existing")" != "$repo_sha" ]; then
  echo "warning: $existing is not the pinned launcher $repo_version; $bin/repo will be" >&2
fi
mkdir -p "$bin"
mv "$work/repo" "$bin/repo"
chmod +x "$bin/repo"
echo "repo launcher $repo_version installed to $bin/repo"

# pixi second, because nothing above it needs pixi and the manifest that pins it
# is already on disk by now.
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) want=linux-64 ;;
  Linux/aarch64 | Linux/arm64) want=linux-aarch64 ;;
  Darwin/arm64) want=osx-arm64 ;;
  Darwin/x86_64) want=osx-64 ;;
  *) echo "no bootstrap row for $(uname -s)/$(uname -m); add one to bootstrap-pins.txt" >&2; exit 1 ;;
esac

pixi_version=$(awk '$1=="pixi" && $2=="version"{print $3}' "$pins")
pixi_source=$(awk '$1=="pixi" && $2=="source"{print $3}' "$pins")
set -- $(awk -v p="$want" '$1=="pixi" && $2=="platform" && $3==p {print $4, $5, $6}' "$pins")
[ $# -eq 3 ] || { echo "bootstrap-pins.txt has no complete pixi row for $want" >&2; exit 1; }
asset=$1 sha=$2 member=$3

if [ -x "$pixi_bin/pixi" ] && "$pixi_bin/pixi" --version 2>/dev/null | grep -qx "pixi $pixi_version"; then
  echo "pixi $pixi_version already at $pixi_bin/pixi"
  exit 0
fi

curl -fsSL -o "$work/$asset" "$pixi_source$asset"
got=$(sha_of "$work/$asset")
[ "$got" = "$sha" ] || { echo "checksum mismatch for $asset: got $got, pinned $sha" >&2; exit 1; }

tar -xzf "$work/$asset" -C "$work" "$member"
mkdir -p "$pixi_bin"
mv "$work/$member" "$pixi_bin/pixi"
chmod +x "$pixi_bin/pixi"
echo "pixi $pixi_version installed to $pixi_bin/pixi; put $bin and $pixi_bin on PATH"
