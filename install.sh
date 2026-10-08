#!/usr/bin/env bash
# First-run setup and launch. Safe to re-run: it never overwrites an existing .env.
#
#   ./install.sh                set up, then run the dashboard in the foreground
#   ./install.sh --background   set up, then run it detached (for agents and SSH sessions)
#   ./install.sh --no-launch    set up only; start later with ./start.sh
set -euo pipefail
cd "$(dirname "$0")"

MODE=foreground
for arg in "$@"; do
  case "$arg" in
    --background|-b) MODE=background ;;
    --no-launch|-n)  MODE=none ;;
    -h|--help)       sed -n '2,6p' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }
ok()   { printf '✓ %s\n' "$*"; }

# ── Python ────────────────────────────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || fail "Python 3 is required but was not found."
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
  || fail "Python 3.8 or newer is required (found: $(python3 --version 2>&1))."
ok "$(python3 --version 2>&1)"

# ── .env ──────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  ok "created private .env from .env.example"
else
  ok "existing .env preserved"
fi

# Read one setting from .env without evaluating the file (it may hold secrets).
envval() {
  local line
  line=$(grep -E "^[[:space:]]*$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r') || true
  line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
  printf '%s' "$line"
}
PORT="${JARVIS_PORT:-$(envval JARVIS_PORT)}"; PORT="${PORT:-8730}"
HERMES_CMD_CFG="${HERMES_CMD:-$(envval HERMES_CMD)}"

# ── Hermes Agent ──────────────────────────────────────────────────────────────
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
if [ -n "$HERMES_CMD_CFG" ]; then
  # shellcheck disable=SC2086
  hermes_version=$($HERMES_CMD_CFG --version 2>&1 | head -n1) \
    || fail "HERMES_CMD is '$HERMES_CMD_CFG' but running it failed: $hermes_version"
elif command -v hermes >/dev/null 2>&1; then
  hermes_version=$(hermes --version 2>&1 | head -n1) \
    || fail "hermes is on PATH but 'hermes --version' failed: $hermes_version"
else
  cat >&2 <<'EOF'

✗ Hermes Agent is required but was not found on PATH.
  Install it, run its setup wizard, then run ./install.sh again:

    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
    hermes setup

  If hermes is installed somewhere unusual, set HERMES_CMD=/absolute/path/to/hermes in .env.
EOF
  exit 1
fi
ok "Hermes: $hermes_version"

# ── ElevenLabs (optional) ─────────────────────────────────────────────────────
if [ -n "$(envval ELEVENLABS_API_KEY)" ]; then
  ok "ElevenLabs key present in .env (the server validates it at startup; it is never printed)"
else
  printf '· no ELEVENLABS_API_KEY in .env — browser speech will be used.\n'
  printf '  Paste a key into .env at any time; the running server picks it up automatically.\n'
fi

chmod +x start.sh install.sh

# ── Already running? ──────────────────────────────────────────────────────────
if ./start.sh --status 2>/dev/null; then
  printf '\nJARVIS is already running.  Dashboard: http://127.0.0.1:%s\n' "$PORT"
  printf 'Restart with:  ./start.sh --stop && ./start.sh --background\n\n'
  exit 0
fi

printf '\nJARVIS is ready.  Dashboard: http://127.0.0.1:%s\n\n' "$PORT"
case "$MODE" in
  none)       printf 'Start it with ./start.sh (foreground) or ./start.sh --background\n' ;;
  background) exec ./start.sh --background ;;
  *)          exec ./start.sh ;;
esac
