#!/usr/bin/env bash
# Start a Redroid-style image, wait for boot, save screenshot and logs to /work/out/<name>.
# usage: boot_test.sh <image> <name> <minutes>
img=$1; name=$2; minutes=$3
out=/work/out/$name; mkdir -p "$out"
docker rm -f "$name" >/dev/null 2>&1

docker run -d --privileged --name "$name" -p 5555:5555 "$img" \
  androidboot.redroid_width=1080 androidboot.redroid_height=2400 androidboot.redroid_dpi=440 \
  androidboot.redroid_gpu_mode=guest androidboot.selinux=permissive

ok=0
for i in $(seq $((minutes * 6))); do
  sleep 10
  docker ps -q -f name="$name" | grep -q . || { echo "container exited"; break; }
  adb connect localhost:5555 >/dev/null 2>&1
  [ "$(adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && { ok=1; break; }
  # mid-boot snapshot helps see how far it got
  [ $((i % 30)) -eq 0 ] && adb -s localhost:5555 exec-out screencap -p > "$out/progress_$i.png" 2>/dev/null
done
echo "boot_completed=$ok after ${i}x10s" | tee "$out/result.txt"

sleep 20
adb -s localhost:5555 exec-out screencap -p > "$out/screen.png" 2>/dev/null
adb -s localhost:5555 shell getprop > "$out/getprop.txt" 2>&1
adb -s localhost:5555 logcat -d -b all > "$out/logcat.txt" 2>&1
adb -s localhost:5555 shell dmesg > "$out/dmesg.txt" 2>&1
docker logs "$name" > "$out/container.txt" 2>&1
grep -iE 'FATAL|crash|died|critical process|cannot link|not found' "$out/logcat.txt" "$out/container.txt" | head -300 > "$out/errors.txt"
adb disconnect >/dev/null 2>&1
docker rm -f "$name" >/dev/null 2>&1
find "$out" -empty -delete
[ $ok = 1 ]
