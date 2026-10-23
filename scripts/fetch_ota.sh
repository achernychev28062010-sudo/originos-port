#!/usr/bin/env bash
# Download an official vivo OTA zip and unpack the partitions the port needs.
# usage: fetch_ota.sh <ota_url> <out_dir>
set -ex
url=$1; out=$2
mkdir -p "$out"; cd "$out"

aria2c -q -x16 -s16 -o ota.zip "$url"
payload-dumper-go -l ota.zip | tee /work/out/partitions.txt

# only the generic side: vivo vendor/odm are tied to MediaTek hardware, Redroid supplies its own
payload-dumper-go -c "$(nproc)" -p system,system_ext,product -o img ota.zip
rm -f ota.zip

# root ownership, modes and xattrs (file capabilities) must survive, so copy from a real mount
for img in img/*.img; do
  name=$(basename "$img" .img)
  sudo mkdir -p "fs/$name" "/mnt/$name"
  file -s "$img" | tee -a /work/out/partitions.txt
  if sudo mount -t erofs -o loop,ro "$img" "/mnt/$name"; then
    sudo cp -a "/mnt/$name/." "fs/$name/" && sudo umount "/mnt/$name"
  else
    sudo fsck.erofs --extract="fs/$name" --preserve "$img"
  fi
  rm -f "$img"
done

# keep the identity of the build for the report
for p in fs/system/system/build.prop fs/system_ext/etc/build.prop fs/product/etc/build.prop fs/vendor/build.prop; do
  [ -f "$p" ] && { echo "== $p"; grep -E 'ro\.(build|vivo|product|system)\.' "$p"; }
done > /work/out/build_props.txt 2>&1 || true
sudo du -sh fs/* | tee -a /work/out/partitions.txt
