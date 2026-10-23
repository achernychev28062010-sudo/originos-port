#!/usr/bin/env bash
# Keep sshd reachable as bore.pub:<port>. bore.pub silently drops idle tunnels while the
# local client keeps running, so probe the public port through the tunnel itself and
# restart the client on the same port when the probe fails.
port=""
while true; do
  if [ -z "$port" ]; then
    bore local 22 --to bore.pub > /tmp/bore.log 2>&1 &
    sleep 5
    port=$(grep -o 'bore.pub:[0-9]*' /tmp/bore.log | head -1 | cut -d: -f2)
  elif ! timeout 10 bash -c "exec 3<>/dev/tcp/bore.pub/$port && head -c 4 <&3 | grep -q SSH"; then
    pkill -x bore; sleep 2
    bore local 22 --to bore.pub --port "$port" >> /tmp/bore.log 2>&1 &
    echo "$(date +%T) reconnected" >> /tmp/bore.log
  fi
  sleep 30
done
