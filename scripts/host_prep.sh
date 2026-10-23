#!/usr/bin/env bash
# Prepare the arm64 runner: free disk, load binder for Redroid, install tools.
set -x
sudo mkdir -p /work/out && sudo chown -R "$USER" /work

sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache /usr/local/share/boost 2>/dev/null
docker system prune -af >/dev/null 2>&1

sudo apt-get update -qq
sudo apt-get install -y -qq aria2 erofs-utils adb "linux-modules-extra-$(uname -r)" || \
  sudo apt-get install -y -qq aria2 erofs-utils adb

sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
sudo modprobe erofs || true

ver=1.3.0
curl -sL "https://github.com/ssut/payload-dumper-go/releases/download/$ver/payload-dumper-go_${ver}_linux_arm64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin payload-dumper-go

{
  uname -a; echo; df -h; echo; free -h; echo; nproc
  echo; grep -E 'binder|erofs' /proc/filesystems
  echo; ls -l /dev/binder* /dev/dri 2>&1
} | tee /work/out/host.txt
