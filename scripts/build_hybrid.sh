#!/usr/bin/env bash
# Build a Redroid image that runs OriginOS: vivo system/system_ext/product on top of
# Redroid's container-aware init and vendor (virtual GPU, no phone hardware).
# usage: build_hybrid.sh <redroid_image> <ota_dir from fetch_ota.sh> <out_tag>
set -ex
base=$1; ota=$2/fs; tag=$3
R=/work/redroid; O=/work/rootfs
sudo rm -rf "$R" "$O"; sudo mkdir -p "$R" "$O"

cid=$(docker create "$base")
docker export "$cid" | sudo tar -x -C "$R"
docker rm "$cid"
entry=$(docker inspect -f '{{json .Config.Entrypoint}}' "$base")
docker rmi "$base" || true

# 1. OriginOS system-as-root is the new root
sudo cp -a "$ota/system/." "$O/"
for part in system_ext product odm; do
  [ -d "$ota/$part" ] || continue
  sudo rm -rf "$O/$part" "$O/system/$part"
  sudo cp -a "$ota/$part" "$O/$part"
  sudo ln -s "/$part" "$O/system/$part"
done
sudo rm -rf "$ota"

# 2. Redroid hardware layer: vendor (+ odm if vivo has none)
sudo rm -rf "$O/vendor"; sudo cp -a "$R/vendor" "$O/vendor"
[ -d "$O/odm" ] || { [ -d "$R/odm" ] && sudo cp -a "$R/odm" "$O/odm"; }

# 3. Redroid init knows it runs in a container (no first stage, no real partitions)
sudo cp -a "$R/system/bin/init" "$O/system/bin/init"
sudo ln -sfn /system/bin/init "$O/init"
[ -f "$R/system/etc/init/redroid.rc" ] && sudo cp -a "$R/system/etc/init/redroid.rc" "$O/system/etc/init/" || true
sudo rm -rf "$R"

ls -la "$O" > /work/out/rootfs_ls.txt
sudo tar --xattrs -C "$O" -c . | docker import -c "ENTRYPOINT $entry" - "$tag"
sudo rm -rf "$O"
docker images | tee -a /work/out/rootfs_ls.txt
