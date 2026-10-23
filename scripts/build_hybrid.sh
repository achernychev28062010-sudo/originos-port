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
for part in system_ext product; do
  [ -d "$ota/$part" ] || continue
  sudo rm -rf "$O/$part" "$O/system/$part"
  sudo cp -a "$ota/$part" "$O/$part"
  sudo ln -s "/$part" "$O/system/$part"
done
sudo rm -rf "$ota"

# 2. Redroid hardware layer: vendor and odm
for part in vendor odm; do
  sudo rm -rf "$O/$part"
  [ -d "$R/$part" ] && sudo cp -a "$R/$part" "$O/$part" || sudo mkdir -p "$O/$part"
done

# 3. init: OriginOS's own by default. Redroid 15 init is linked against Android 15 libs
#    (fmt v11) and cannot load on OriginOS 7's Android 17 libraries.
if [ "${INIT_FROM:-originos}" = redroid ]; then
  sudo cp -a "$R/system/bin/init" "$O/system/bin/init"
fi
sudo ln -sfn /system/bin/init "$O/init"
# OriginOS turns on 32-bit zygote; Redroid's vendor and the runner only do 64-bit.
# product props load last, so they win.
sudo tee -a "$O/product/etc/build.prop" >/dev/null <<'EOF'
# container port overrides
ro.zygote=zygote64
ro.product.cpu.abilist=arm64-v8a
ro.product.cpu.abilist32=
ro.product.cpu.abilist64=arm64-v8a
ro.vendor.init_dev_config=/dev/null
EOF
[ -f "$R/system/etc/init/redroid.rc" ] && sudo cp -a "$R/system/etc/init/redroid.rc" "$O/system/etc/init/" || true
[ -n "${KEEP:-}" ] || sudo rm -rf "$R"

{ ls -la "$O"; ls -la "$O/system/bin/init" "$O/system/bin/app_process64"; getcap "$O/system/bin/"* 2>/dev/null | head; } > /work/out/rootfs_ls.txt
sudo tar --xattrs --xattrs-include='*' -C "$O" -c . | docker import -c "ENTRYPOINT $entry" - "$tag"
[ -n "${KEEP:-}" ] || sudo rm -rf "$O"
docker images | tee -a /work/out/rootfs_ls.txt
