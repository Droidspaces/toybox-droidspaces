#!/bin/bash
set -eo pipefail

TOOLCHAINS_DIR="${TOOLCHAINS_DIR:-${HOME}/toolchains}"
OUT_DIR="$(pwd)/out"
ARCHS=("aarch64" "armhf" "x86" "x86_64")

show_help() {
  echo "Usage: ./build-cross.sh [options]"
  echo
  echo "Options:"
  echo "  -h, --help   Show this help message"
  echo "  -c, --clean  Clean workspace and build artifacts, then exit"
  echo
  echo "This script strictly forces the use of droidspaces.config for all targets."
  exit 0
}

# Parse simple options
CLEAN=false
for arg in "$@"; do
  if [ "$arg" = "-c" ] || [ "$arg" = "--clean" ]; then
    CLEAN=true
  elif [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
    show_help
  fi
done

if [ "$CLEAN" = true ]; then
  echo "Cleaning up workspace and build artifacts..."
  make distclean  || true
  rm -rf "$OUT_DIR"
  echo "Cleanup complete."
  exit 0
fi

if [ ! -f "droidspaces.config" ]; then
  echo "Error: droidspaces.config not found!" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

declare -A ARCH_MAP=(
  [aarch64]="aarch64-linux-musl-cross:aarch64-linux-musl-:toybox-aarch64"
  [armhf]="arm-linux-musleabihf-cross:arm-linux-musleabihf-:toybox-armhf"
  [x86]="i686-linux-musl-cross:i686-linux-musl-:toybox-x86"
  [x86_64]="x86_64-linux-musl-cross:x86_64-linux-musl-:toybox-x86_64"
)

ORIGINAL_PATH="$PATH"

for arch in "${ARCHS[@]}"; do
  echo "=== Building architecture: $arch ==="

  IFS=":" read -r arch_dir prefix binary_name <<< "${ARCH_MAP[$arch]}"
  toolchain_path="${TOOLCHAINS_DIR}/${arch_dir}"

  if [ ! -d "$toolchain_path" ]; then
    echo "Error: Toolchain directory not found at $toolchain_path" >&2
    continue
  fi

  export PATH="${toolchain_path}/bin:${ORIGINAL_PATH}"
  export CROSS_COMPILE="$prefix"
  export LDFLAGS="--static"

  echo "Cleaning build tree..."
  make clean  || true

  echo "Forcing droidspaces.config..."
  cp droidspaces.config .config

  echo "Compiling static binary..."
  if make toybox -j$(nproc) ; then
    target_binary="${OUT_DIR}/${binary_name}"
    rm -f "$target_binary"
    cp toybox "$target_binary"

    if command -v "${prefix}strip" ; then
      chmod +w "$target_binary"
      "${prefix}strip" "$target_binary"
      chmod -w "$target_binary"
    fi

    size_bytes=$(stat -c %s "$target_binary")
    echo "Success: Built $target_binary (${size_bytes} bytes)"
  else
    echo "Error: Compilation failed for $arch" >&2
  fi
done

export PATH="$ORIGINAL_PATH"
echo "All builds completed."
