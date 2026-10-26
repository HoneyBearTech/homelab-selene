# Selene's own steps in scripts/smoke-test.sh, which sources this file; it isn't run on its own.
# shellcheck shell=bash
# shellcheck disable=SC2154 # work, root, busybox and fail come from smoke-test.sh

smoke_busy_checked=false

# The scheduled backup must not stop USAS while it runs a playbook (scripts/backup-stack.sh). Once, while the stack
# is up: with a run record saying "running", and then with an ansible-playbook process in the container, the
# scheduled backup waits, gives up and fails, takes no backup and leaves USAS running; with neither, USAS isn't busy.
smoke_check() {
  if $smoke_busy_checked; then return 0; fi
  smoke_busy_checked=true
  local id started out
  id=$(compose ps --quiet usas)
  started=$(docker inspect --format '{{.State.StartedAt}}' "$id")
  printf 'BACKUP_DIR=%s\nBACKUP_BUSY_TIMEOUT=2\nBACKUP_BUSY_INTERVAL=1\n' "$work/busy-backups" >"$work/busy.env"
  expect_wait() {
    if out=$(BACKUP_ENV_FILE=$work/busy.env "$root/scripts/scheduled-backup.sh" 2>&1); then
      fail "the scheduled backup ran while $1"
    fi
    echo "$out" | grep -q "still busy" || fail "the scheduled backup didn't say it waited while $1: $out"
    [ ! -e "$work/busy-backups" ] || [ -z "$(ls -A "$work/busy-backups")" ] || fail "a backup was taken while $1"
    [ "$(docker inspect --format '{{.State.StartedAt}}' "$id")" = "$started" ] || fail "USAS was stopped while $1"
    echo "The scheduled backup waited and left USAS running while $1"
  }

  docker run --rm --network none --volumes-from "$id" "$busybox" sh -c \
    'mkdir -p /data/runs && echo "{\"id\": \"smoke-busy\", \"action\": \"site\", \"status\": \"running\"}" \
      >/data/runs/smoke-busy.json && chown -R 10001:10001 /data/runs' </dev/null
  expect_wait "a web UI run was in progress"
  docker run --rm --network none --volumes-from "$id" "$busybox" rm /data/runs/smoke-busy.json </dev/null

  docker exec -d "$id" sh -c 'ln -sf "$(command -v python)" /tmp/ansible-playbook &&
    exec /tmp/ansible-playbook -c "import time; time.sleep(60)"'
  sleep 2
  expect_wait "ansible-playbook ran in the container"
  docker exec "$id" python -c '
import os, signal
for pid in os.listdir("/proc"):
    if pid.isdigit():
        try:
            argv = open("/proc/%s/cmdline" % pid, "rb").read().split(b"\0")
        except OSError:
            continue
        if argv[0] == b"/tmp/ansible-playbook":
            os.kill(int(pid), signal.SIGTERM)
'
  sleep 1

  # shellcheck source=scripts/backup-stack.sh
  . "$root/scripts/backup-stack.sh"
  if out=$(backup_busy); then fail "USAS still counts as busy with no run: $out"; fi
  echo "With no run in progress, USAS isn't busy"
}
