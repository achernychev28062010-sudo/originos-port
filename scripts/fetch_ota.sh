#!/usr/bin/env bash
# Download an official vivo OTA zip and unpack the partitions the port needs.
# usage: fetch_ota.sh <ota_url> <out_dir>
set -ex
url=$1; out=$2
mkdir -p "$out"; cd "$out"

aria2c -q -x16 -s16 -o ota.zip "$url"
payload-dumper-go -l ota.zip | tee /work/out/partitions.txt

# vivo keeps extra framework bits in odm/vendor-side partitions; take what exists
want=system,system_ext,product,odm,vendor
payload-dumper-go -c "$(nproc)" -p "$want" -o img ota.zip || payload-dumper-go -c "$(nproc)" -p system,system_ext,product -o img ota.zip
rm -f ota.zip

for img in img/*.img; do
  name=$(basename "$img" .img)
  mkdir -p "fs/$name"
  file -s "$img" | tee -a /work/out/partitions.txt
  if ! fsck.erofs --extract="fs/$name" "$img" >/dev/null 2>&1; then
    sudo mkdir -p "/mnt/$name" && sudo mount -o loop,ro "$img" "/mnt/$name"
    sudo cp -a "/mnt/$name/." "fs/$name/" && sudo umount "/mnt/$name"
  fi
  rm -f "$img"
done

# keep the identity of the build for the report
for p in fs/system/system/build.prop fs/system_ext/etc/build.prop fs/product/etc/build.prop fs/vendor/build.prop; do
  [ -f "$p" ] && { echo "== $p"; grep -E 'ro\.(build|vivo|product|system)\.' "$p"; }
done > /work/out/build_props.txt 2>&1 || true
du -sh fs/* | tee -a /work/out/partitions.txt
