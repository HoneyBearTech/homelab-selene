# Selene's part of scripts/scheduled-backup.sh, which sources this file; it isn't run on its own.
# The backup stops USAS while its data is copied, and a playbook run in progress would end with it (a VM half
# installed, a baseline half applied). backup_busy succeeds, and says why, while USAS runs a playbook:
# - a run the web UI started: its record in /data/runs/<id>.json says "running" (USAS marks a record it finds
#   "running" at start-up as "interrupted", so a stale one can't keep the backup waiting);
# - a run started on the command line (docker exec usas ansible-playbook ...): an ansible-playbook process.
# It fails (not busy) when USAS isn't running, since then there is nothing to interrupt.
# shellcheck shell=bash

# Run inside the usas container (no shell tools there beyond Python); exit 0 = busy, with the reason on stdout.
usas_busy_check='
import glob, json, os, sys
for path in glob.glob("/data/runs/*.json"):
    try:
        with open(path) as f:
            run = json.load(f)
    except (OSError, ValueError):
        continue
    if isinstance(run, dict) and run.get("status") == "running":
        print("USAS run %s (%s) is in progress" % (run.get("id"), run.get("action")))
        sys.exit(0)
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        with open("/proc/%s/cmdline" % pid, "rb") as f:
            argv = f.read().split(b"\0")
    except OSError:
        continue
    if any(arg.endswith(b"/ansible-playbook") or arg == b"ansible-playbook" for arg in argv):
        print("an ansible-playbook process (pid %s) is running in the usas container" % pid)
        sys.exit(0)
sys.exit(1)
'

backup_busy() {
  local id
  id=$(docker compose ps --quiet --status running usas 2>/dev/null) || return 1
  if [ -z "$id" ]; then return 1; fi
  docker exec "$id" python -I -c "$usas_busy_check" 2>/dev/null
}
