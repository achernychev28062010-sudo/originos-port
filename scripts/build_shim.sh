#!/usr/bin/env bash
# Build shim/selinux_shim.c for bionic arm64 with the host clang, linking against the
# OriginOS libc so DT_NEEDED resolves to the copy init already has loaded.
# usage: build_shim.sh <rootfs> <out.so>
set -e
root=$1; out=$2
here=$(dirname "$0")/..
clang --target=aarch64-linux-android35 -fPIC -O2 -shared -nostdlib -fuse-ld=lld \
  -Wl,-soname,libselinux_shim.so -Wl,--hash-style=both \
  "$here/shim/selinux_shim.c" "$root/system/lib64/bootstrap/libc.so" -o "$out"
