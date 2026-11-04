#!/usr/bin/env bash
# Simulate a server restart on the isolated CI account, never reboot the host.
set -euo pipefail
task_fixture_root=$1
test "${GITHUB_ACTIONS:-}" = true
test "$(id -u shotbot)" = 555
test -f "$task_fixture_root/build/sshd_config"
while true; do
  if test -f /Users/shotbot/.sigma-test-restart; then
    sudo rm -f /Users/shotbot/.sigma-test-restart
    if test -f "$task_fixture_root/build/sshd.pid"; then
      sudo kill "$(cat "$task_fixture_root/build/sshd.pid")" || true
    fi
    sudo pkill -KILL -u shotbot || true
    sleep 3
    sudo /usr/sbin/sshd -f "$task_fixture_root/build/sshd_config" -E "$task_fixture_root/build/sshd.log"
    echo "Isolated SSH fixture restarted"
  fi
  sleep 0.5
done
