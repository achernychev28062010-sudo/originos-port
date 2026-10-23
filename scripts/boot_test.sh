#!/usr/bin/env bash
# Start a Redroid-style image, wait for boot, save screenshot and logs to /work/out/<name>.
# usage: boot_test.sh <image> <name> <minutes> [gpu_mode]
img=$1; name=$2; minutes=$3; gpu=${4:-guest}
out=/work/out/$name; mkdir -p "$out"
dev=localhost:5555
a() { timeout 60 adb -s $dev "$@"; }
docker rm -f "$name" >/dev/null 2>&1
sudo dmesg -C

docker run -d --privileged --name "$name" -p 5555:5555 "$img" \
  androidboot.redroid_width=1080 androidboot.redroid_height=2400 androidboot.redroid_dpi=440 \
  androidboot.redroid_gpu_mode=$gpu androidboot.selinux=permissive

ok=0
for i in $(seq $((minutes * 6))); do
  sleep 10
  docker ps -q -f name="$name" | grep -q . || { echo "container exited"; break; }
  timeout 10 adb connect $dev >/dev/null 2>&1
  [ "$(a shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && { ok=1; break; }
  # mid-boot snapshot helps see how far it got
  [ $((i % 30)) -eq 0 ] && a exec-out screencap -p > "$out/progress_$i.png" 2>/dev/null
done
echo "boot_completed=$ok after ${i}x10s" | tee "$out/result.txt"
docker inspect -f 'state={{.State.Status}} exit={{.State.ExitCode}} err={{.State.Error}}' "$name" | tee -a "$out/result.txt"

if docker ps -q -f name="$name" | grep -q .; then
  sleep 20
  a exec-out screencap -p > "$out/screen.png" 2>/dev/null
  a shell getprop > "$out/getprop.txt" 2>&1
  a logcat -d -b all > "$out/logcat.txt" 2>&1
fi
# Android init writes to kmsg, which lands in the host kernel log
sudo dmesg > "$out/host_dmesg.txt"
docker logs "$name" > "$out/container.txt" 2>&1
grep -hiE 'Abort message|FATAL|critical process|cannot link|CANNOT LINK|init: .*(fail|error)' \
  "$out/logcat.txt" "$out/host_dmesg.txt" "$out/container.txt" 2>/dev/null | sort | uniq -c | sort -rn | head -150 > "$out/errors.txt"
timeout 10 adb disconnect >/dev/null 2>&1
docker rm -f "$name" >/dev/null 2>&1
find "$out" -empty -delete
[ $ok = 1 ]
