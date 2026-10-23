#!/usr/bin/env bash
# Start the OriginOS image the way a first-stage ramdisk would have prepared it.
# Android 17's /system/bin/init only does selinux_setup/second_stage, so the container
# supplies what first stage init normally creates, plus SELinux shims for a host
# kernel without SELinux.
# usage: run_container.sh <image> <name> [port]
img=$1; name=$2; port=${3:-5555}
here=$(cd "$(dirname "$0")/.." && pwd)
shim=/work/shim; mkdir -p $shim

# docker replaces the /etc -> /system/etc symlink with its own dir (hosts, resolv.conf),
# hiding cgroups.json and friends; /etc is mounted from the unpacked system below
bash "$here/scripts/build_shim.sh" /work/rootfs $shim/libselinux_shim.so

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
sudo mkdir -p $shim/rc
for f in $(sudo grep -l reboot_on_failure /work/rootfs/vendor/etc/init/*.rc 2>/dev/null); do
  sudo sed '/reboot_on_failure/d' "$f" | sudo tee $shim/rc/$(basename "$f") >/dev/null
  ovr="$ovr -v $shim/rc/$(basename "$f"):${f#/work/rootfs}:ro"
done
sudo cp "$here/shim/container.rc" $shim/
# init skips rc files not owned by root or writable by group/others
sudo chown -R root:root $shim/rc $shim/container.rc
sudo chmod 644 $shim/rc/* $shim/container.rc

# vivo's cgroup layout (v1 cpuset/schedtune/blkio) cannot be mounted on a cgroup v2 host,
# Android 17 gives up on the first failed controller, and enabling v2 controllers in the
# container's root cgroup hits EBUSY. Without cgroups.json init skips cgroup setup and
# services start in the container's own cgroup, which is what we want.
E=/work/rootfs/system/etc
for j in cgroups.json task_profiles.json; do
  [ -f $E/$j.vivo ] || sudo cp -a $E/$j $E/$j.vivo
done
sudo rm -f $E/cgroups.json
sudo cp -a /work/redroid/system/etc/task_profiles.json $E/task_profiles.json

# userdata/metadata are their own partitions on a phone; here they must be separate
# mounts, because init.rc remounts / read-only in post-fs. RESET=1 wipes them.
[ -n "${RESET:-}" ] && sudo rm -rf /work/data /work/metadata
sudo mkdir -p /work/data /work/metadata

docker run -d --privileged --name "$name" -p $port:5555 \
  -v /work/data:/data -v /work/metadata:/metadata \
  --tmpfs /dev/socket:mode=0755 \
  --device /dev/mapper/control:/dev/device-mapper \
  -v $shim/devblock:/dev/block \
  -v /work/rootfs/system/etc:/etc \
  -v $shim/libselinux_shim.so:/system/lib64/libselinux_shim.so:ro \
  -v $shim/libselinux_shim.so:/vendor/lib64/libselinux_shim.so:ro \
  -v $shim/container.rc:/system/etc/init/container.rc:ro \
  $ovr \
  -e LD_PRELOAD=/system/lib64/libselinux_shim.so \
  --entrypoint /init "$img" second_stage
