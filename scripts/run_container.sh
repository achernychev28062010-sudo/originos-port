#!/usr/bin/env bash
# Start the OriginOS image the way a first-stage ramdisk would have prepared it.
# Android 17's /system/bin/init only does selinux_setup/second_stage, so the container
# supplies what first stage init normally creates, plus SELinux shims for a host
# kernel without SELinux.
# usage: run_container.sh <image> <name> [port]
img=$1; name=$2; port=${3:-5555}
here=$(cd "$(dirname "$0")/.." && pwd)
shim=/work/shim; mkdir -p $shim

[ -f $shim/libselinux_shim.so ] || bash "$here/scripts/build_shim.sh" /work/rootfs $shim/libselinux_shim.so
cp "$here/shim/container.rc" $shim/

# apexd attaches loop devices; nodes must exist before start because the container
# gets a snapshot of /dev
sudo mkdir -p $shim/devblock
for i in $(seq 0 127); do
  [ -e /dev/loop$i ] || sudo mknod /dev/loop$i b 7 $i
  [ -e $shim/devblock/loop$i ] || sudo mknod $shim/devblock/loop$i b 7 $i
done
docker rm -f "$name" >/dev/null 2>&1; sleep 1
sudo dmsetup remove_all -f 2>/dev/null; sudo losetup -D

# Redroid vendor services that fail in the port must not reboot the system
ovr=""
mkdir -p $shim/rc
for f in $(sudo grep -l reboot_on_failure /work/rootfs/vendor/etc/init/*.rc 2>/dev/null); do
  sudo sed '/reboot_on_failure/d' "$f" > $shim/rc/$(basename "$f")
  ovr="$ovr -v $shim/rc/$(basename "$f"):${f#/work/rootfs}:ro"
done

docker run -d --privileged --name "$name" -p $port:5555 \
  --tmpfs /dev/socket:mode=0755 \
  --device /dev/mapper/control:/dev/device-mapper \
  -v $shim/devblock:/dev/block \
  -v $shim/libselinux_shim.so:/system/lib64/libselinux_shim.so:ro \
  -v $shim/container.rc:/system/etc/init/container.rc:ro \
  $ovr \
  -e LD_PRELOAD=/system/lib64/libselinux_shim.so \
  --entrypoint /init "$img" second_stage
