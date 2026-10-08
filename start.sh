#!/usr/bin/env bash
# Launcher.
#   ./start.sh               run in the foreground (Ctrl-C stops it)
#   ./start.sh --background  run detached; output in jarvis.log, pid in .jarvis.pid
#   ./start.sh --stop        stop a --background instance
#   ./start.sh --status      print a one-line status; exit 0 if the dashboard answers
set -euo pipefail
cd "$(dirname "$0")"

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export JARVIS_RUNTIME="${JARVIS_RUNTIME:-auto}"

envval() {
  local line
  line=$(grep -E "^[[:space:]]*$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r') || true
  line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
  printf '%s' "$line"
}
PORT="${JARVIS_PORT:-$(envval JARVIS_PORT)}"; PORT="${PORT:-8730}"
URL="http://127.0.0.1:$PORT"
PIDFILE=.jarvis.pid
LOG=jarvis.log

need_python() {
  command -v python3 >/dev/null 2>&1 \
    || { printf 'JARVIS needs Python 3. Install Python, then run this script again.\n' >&2; exit 1; }
}

# Is anything answering on the port? (/api/status also probes Hermes, so allow time.)
status() {
  python3 - "$URL" <<'EOF'
import json, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1] + "/api/status", timeout=30) as r:
        d = json.load(r)
except Exception:
    sys.exit(1)
voice = "voice=" + ("elevenlabs ok" if d.get("voice_ok") else
                    ("elevenlabs REJECTED: %s" % d.get("voice_error") if d.get("stt") == "elevenlabs"
                     else "browser"))
print(f"running at {sys.argv[1]}  runtime={d.get('runtime')}  profile={d.get('profile')}  {voice}")
EOF
}

case "${1:-}" in
  --status|-s)
    status ;;

  --stop)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      kill "$(cat "$PIDFILE")" && rm -f "$PIDFILE" && printf 'stopped\n'
    else
      rm -f "$PIDFILE"
      printf 'no background instance recorded in %s\n' "$PIDFILE" >&2
      exit 1
    fi ;;

  --background|-b)
    need_python
    if status 2>/dev/null; then printf 'already running\n'; exit 0; fi
    # Detached mode never pops a browser; the caller reports the URL instead.
    JARVIS_OPEN="${JARVIS_OPEN:-0}" nohup python3 server.py >>"$LOG" 2>&1 &
    echo $! >"$PIDFILE"
    for _ in $(seq 1 60); do
      if python3 -c "import urllib.request; urllib.request.urlopen('$URL/', timeout=2)" >/dev/null 2>&1; then
        status
        printf 'log: %s/%s   stop: ./start.sh --stop\n' "$(pwd)" "$LOG"
        exit 0
      fi
      if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        printf 'server exited early — last lines of %s:\n' "$LOG" >&2
        tail -n 15 "$LOG" >&2
        rm -f "$PIDFILE"
        exit 1
      fi
      sleep 0.5
    done
    printf 'server did not answer within 30s — see %s\n' "$LOG" >&2
    exit 1 ;;

  "")
    need_python
    exec python3 server.py ;;

  *)
    sed -n '2,6p' "$0"; exit 2 ;;
esac
