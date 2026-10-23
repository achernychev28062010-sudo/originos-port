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

# Not --privileged: a privileged container gets the host's /sys and /proc/sys writable,
# and OriginOS (ueventd coldboot, init.rc kernel knobs) took the runner down that way.
# All capabilities instead, so Docker keeps /sys and /proc/sys read-only and masks
# sysrq; devices Android needs are passed explicitly. Memory is capped so a full
# userspace without working lmkd cannot OOM the runner agent.
# userdata/metadata are their own partitions on a phone; here they must be separate
# mounts, because init.rc remounts / read-only in post-fs. RESET=1 wipes them.
[ -n "${RESET:-}" ] && sudo rm -rf /work/data /work/metadata
sudo mkdir -p /work/data /work/metadata

# Device allowlist. ueventd mknods every host device inside the container and vold
# treats the host disk (sda) as removable storage it may repartition: that is what
# corrupted the runner's disk. Only the device classes Android needs are usable.
dm=$(awk '$2=="device-mapper"{print $1}' /proc/devices)
binder=$(awk '$2=="binder"{print $1}' /proc/devices)
rules=""
# misc (10:x) only by minor: 10:130 is /dev/watchdog, and Android's watchdogd arming the
# host watchdog reboots the runner as soon as Android stops petting it.
# fuse 229, device-mapper 236, loop-control 237, uinput 223, tun 200
for r in "c 1:3" "c 1:5" "c 1:7" "c 1:8" "c 1:9" "c 1:11" "c 5:*" "c 136:*" \
         "c 10:229" "c 10:236" "c 10:237" "c 10:223" "c 10:200" \
         "b 7:*" ${dm:+"b $dm:*"} ${binder:+"c $binder:*"}; do
  rules="$rules --device-cgroup-rule=\"$r rmw\""
done

eval docker run -d --name "$name" -p $port:5555 \
  --cap-add ALL --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
  $rules \
  --device /dev/kmsg --device /dev/fuse --device /dev/loop-control \
  --device /dev/mapper/control:/dev/device-mapper \
  -v /work/data:/data -v /work/metadata:/metadata \
  --memory 11g --memory-swap 11g --cpus 3 \
  --tmpfs /dev/socket:mode=0755 \
  -v $shim/devblock:/dev/block \
  -v /work/rootfs/system/etc:/etc \
  -v $shim/libselinux_shim.so:/system/lib64/libselinux_shim.so:ro \
  -v $shim/libselinux_shim.so:/vendor/lib64/libselinux_shim.so:ro \
  -v $shim/container.rc:/system/etc/init/container.rc:ro \
  $ovr \
  -e LD_PRELOAD=/system/lib64/libselinux_shim.so \
  --entrypoint /init "$img" second_stage
