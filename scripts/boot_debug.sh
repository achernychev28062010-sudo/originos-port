#!/usr/bin/env bash
# One boot attempt of the port with a readable summary: last init events, crash counts,
# boot props, and a screenshot in /work/out if the screen comes up.
# usage: [RESET=1] [WAIT=secs] boot_debug.sh
cd "$(dirname "$0")/.."
command -v clang >/dev/null || sudo apt-get install -y -qq clang lld llvm >/dev/null 2>&1
mkdir -p /work/out
sudo dmesg -C
echo "$(date +%T) starting container"
bash scripts/run_container.sh originos:port oo >/dev/null || exit 1
# heartbeat in the job log: if the runner dies mid-boot, the last lines show why
for _ in $(seq $(( ${WAIT:-240} / 5 ))); do
  sleep 5
  echo "$(date +%T) $(free -m | awk '/Mem/{print "host used " $3 "M avail " $7 "M"}') load $(cut -d' ' -f1 /proc/loadavg) | $(sudo dmesg | grep -cE 'init: starting service') starts | $(sudo dmesg | grep -E 'init: (starting service|Service .*(exited|received))' | tail -1 | cut -c1-110)"
done
docker inspect -f 'state={{.State.Status}} exit={{.State.ExitCode}}' oo
sudo dmesg > /work/out/dmesg.txt
echo "--- last init events"
grep -E 'init:' /work/out/dmesg.txt | grep -vE 'Loading properties|Setting (product )?property|setprop ids|Couldn.t load property|DM_DEV_STATUS|ReadDefaultFstab|processing action|took [0-9]+ms and succeeded|Parsing|import list|converted into|SIGKILL|Have been waiting|Untracked|starting service|\.\.\. started|Command .(copy|write|symlink|mkdir|chown|chmod|start)|task profiles|Created socket|Unable to read config|Could not expand import|ignored duplicate|not found$|encryption policy|NtQ Control|#0[0-9] pc' | tail -"${N:-40}"
echo "--- crashes"
grep -E "received SIG|exited with status [1-9]|critical process|Check failed|failed to get security" /work/out/dmesg.txt | sed 's/^\[[ 0-9.]*\] //; s/pid [0-9]*/pid N/; s/[0-9]*:[0-9]* failed/N failed/' | sort | uniq -c | sort -rn | head -25
timeout 10 adb connect localhost:5555 >/dev/null 2>&1
if timeout 20 adb -s localhost:5555 shell getprop > /work/out/getprop.txt 2>/dev/null; then
  grep -E 'boot_completed|init.svc.(zygote|surfaceflinger|system_server|keystore2|vold)\]' /work/out/getprop.txt
  timeout 30 adb -s localhost:5555 exec-out screencap -p > /work/out/screen.png && echo "screenshot saved"
fi
