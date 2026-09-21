#!/usr/bin/env bash
# herdr-services.sh — start / stop / restart / status / logs for tcm-edu
#
# Manages the Phoenix (:4011) dev server via herdr panes.
# Layout (created on first `start` if missing):
#
#   ┌─────────────┬──────────────────┐
#   │             │ Phoenix  :4011   │  pane $PANE_PHOENIX
#   │  Claude     ├──────────────────┤
#   │             │                  │
#   └─────────────┴──────────────────┘
#
# Phoenix runs in the FOREGROUND of its herdr pane so the user can read
# the live output directly — no /tmp log files.
#
# Usage:
#   bin/herdr-services.sh start    # create pane if needed, launch Phoenix
#   bin/herdr-services.sh stop     # Ctrl-C the pane, force-kill orphans
#   bin/herdr-services.sh restart  # stop + start
#   bin/herdr-services.sh status   # pane + port + HTTP status
#   bin/herdr-services.sh logs     # tail the pane's recent output
#
# Pane discovery: panes are matched by their `cwd` rather than hard-coded
# IDs, so the script survives herdr workspace restarts / ID rotation.

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
WORKSPACE_ROOT="/Users/bai/projects/tcm-edu"
PORT_PHOENIX=4011

PHOENIX_CWD="$WORKSPACE_ROOT"
PHOENIX_CMD="mix phx.server"

# ─── Colors ────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GRN='\033[32m'; RED='\033[31m'; YLW='\033[33m'; CYN='\033[36m'; DIM='\033[2m'; B='\033[1m'; RST='\033[0m'
else
  GRN=''; RED=''; YLW=''; CYN=''; DIM=''; B=''; RST=''
fi

# ─── herdr helpers ─────────────────────────────────────────────────────────
hr()  { printf "${CYN}%s${RST}\n" "──────────────────────────────────────────────────────────────"; }
say() { printf "${B}═══ %s ═══${RST}\n" "$*"; }
ok()  { printf "${GRN}✓${RST} %s\n" "$*"; }
ko()  { printf "${RED}✗${RST} %s\n" "$*"; }
warn(){ printf "${YLW}!${RST} %s\n" "$*"; }

require_herdr() {
  command -v herdr >/dev/null 2>&1 || { ko "herdr not on PATH"; exit 2; }
}

# herdr pane get <id> | python3 -c '...'
pane_field() {
  local pane_id="$1" field="$2"
  herdr pane get "$pane_id" 2>/dev/null \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['pane'].get('$field',''))" 2>/dev/null
}

# Find a pane in the same workspace whose cwd matches $1 AND is NOT a Claude
# agent pane (Claude shares the project root cwd). Returns the pane_id on
# stdout, empty if none.
find_pane_by_cwd() {
  local target_cwd="$1"
  herdr pane list 2>/dev/null \
    | python3 -c "
import sys, json
target = sys.argv[1]
data = json.load(sys.stdin)['result']['panes']
# Skip AI agent sessions; they share cwd with the project root.
candidates = [
    p for p in data
    if p.get('agent') in (None, '', 'unknown')  # terminal panes only
    and (p.get('foreground_cwd','') == target or p.get('cwd','') == target)
]
# Prefer unfocused (terminal panes are usually unfocused when Claude is focused)
candidates.sort(key=lambda p: (p.get('focused', False), p['pane_id']))
if candidates:
    print(candidates[0]['pane_id'])
" "$target_cwd" 2>/dev/null
}

# Find Claude pane in the current project (workspace that contains WORKSPACE_ROOT).
find_claude_pane() {
  herdr pane list 2>/dev/null \
    | python3 -c "
import sys, json
root = sys.argv[1]
data = json.load(sys.stdin)['result']['panes']
for p in data:
    if p.get('agent') == 'claude' and root in (p.get('cwd','') or ''):
        print(p['pane_id']); break
" "$WORKSPACE_ROOT" 2>/dev/null
}

# Send a one-shot command to a pane. Use \n literally via send-text + Enter
# so the shell actually executes it.
pane_exec() {
  local pane_id="$1"; shift
  herdr pane send-text "$pane_id" "$*" >/dev/null
  herdr pane send-keys "$pane_id" Enter >/dev/null
}

pane_interrupt() {
  local pane_id="$1"
  herdr pane send-keys "$pane_id" C-c >/dev/null || true
}

# ─── Port helpers ──────────────────────────────────────────────────────────
port_listening() { lsof -ti :"$1" >/dev/null 2>&1; }
port_pid()       { lsof -ti :"$1" 2>/dev/null | head -1; }
port_http()      { curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:$1/" 2>/dev/null || echo "-"; }

kill_port() {
  local port="$1" label="$2"
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    warn "Force-killing orphan $label processes on :$port (pids=$pids)"
    echo "$pids" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi
}

wait_port() {
  local port="$1" label="$2" max="${3:-30}"
  for _ in $(seq 1 "$max"); do
    if port_listening "$port"; then
      ok "$label listening on :$port"
      return 0
    fi
    sleep 1
  done
  ko "$label did not bind :$port within ${max}s"
  return 1
}

# ─── Pane setup ────────────────────────────────────────────────────────────
ensure_panes() {
  local claude_id
  claude_id=$(find_claude_pane)
  if [ -z "$claude_id" ]; then
    ko "No Claude pane found with cwd under $WORKSPACE_ROOT"
    exit 3
  fi

  PANE_PHOENIX=$(find_pane_by_cwd "$PHOENIX_CWD")

  if [ -z "$PANE_PHOENIX" ]; then
    say "Creating Phoenix pane (right of Claude)"
    PANE_PHOENIX=$(herdr pane split "$claude_id" --direction right --cwd "$PHOENIX_CWD" 2>/dev/null \
      | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['pane']['pane_id'])" 2>/dev/null || true)
    [ -n "$PANE_PHOENIX" ] || { ko "Failed to create Phoenix pane"; exit 4; }
    ok "Phoenix pane: $PANE_PHOENIX"
  fi

  # Save for other commands in the same invocation
  export PANE_PHOENIX
}

# ─── Commands ──────────────────────────────────────────────────────────────
cmd_start() {
  require_herdr
  ensure_panes

  say "Starting Phoenix"

  pane_interrupt "$PANE_PHOENIX"
  sleep 1
  kill_port "$PORT_PHOENIX" "Phoenix"

  local phx_cwd; phx_cwd=$(pane_field "$PANE_PHOENIX" foreground_cwd)
  if [ "$phx_cwd" != "$PHOENIX_CWD" ]; then
    pane_exec "$PANE_PHOENIX" "cd $PHOENIX_CWD && clear"
    sleep 1
  fi

  pane_exec "$PANE_PHOENIX" "echo '━━━ Phoenix :${PORT_PHOENIX} ━━━' && $PHOENIX_CMD"

  echo
  wait_port "$PORT_PHOENIX" "Phoenix" 45
  echo
  ok "Phoenix launched. Run '$0 status' or '$0 logs' to inspect."
}

cmd_stop() {
  require_herdr
  ensure_panes

  say "Stopping Phoenix"
  pane_interrupt "$PANE_PHOENIX"
  sleep 2
  kill_port "$PORT_PHOENIX" "Phoenix"
  ok "Stopped"
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

cmd_status() {
  require_herdr
  ensure_panes

  say "Service status"

  if port_listening "$PORT_PHOENIX"; then
    printf "  ${GRN}●${RST} ${B}%-10s${RST} port=${YLW}%-5s${RST} pid=${DIM}%-7s${RST} http=${GRN}%-4s${RST}\n" \
      "Phoenix" "$PORT_PHOENIX" "$(port_pid $PORT_PHOENIX)" "$(port_http $PORT_PHOENIX)"
  else
    printf "  ${RED}●${RST} ${B}%-10s${RST} port=${YLW}%-5s${RST} ${RED}DOWN${RST}\n" "Phoenix" "$PORT_PHOENIX"
  fi

  hr
  printf "${B}Pane${RST}\n"
  local cwd focus
  cwd=$(pane_field "$PANE_PHOENIX" foreground_cwd)
  focus=$(pane_field "$PANE_PHOENIX" focused)
  [ "$focus" = "True" ] && focus="${GRN}focused${RST}" || focus="${DIM}unfocused${RST}"
  printf "  %s  cwd=%s  %b\n" "$PANE_PHOENIX" "$cwd" "$focus"
}

cmd_logs() {
  require_herdr
  ensure_panes

  say "Phoenix pane $PANE_PHOENIX (last 30 lines)"
  hr
  herdr pane read "$PANE_PHOENIX" --source visible --lines 30 --format text 2>&1 || true
}

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

# ─── Dispatch ──────────────────────────────────────────────────────────────
cmd="${1:-status}"
case "$cmd" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  -h|--help|help) usage ;;
  *)       ko "Unknown command: $cmd"; usage ;;
esac