#!/usr/bin/env bash
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -f /etc/profile.d/agent-app.sh ]; then
  # shellcheck disable=SC1091
  . /etc/profile.d/agent-app.sh
elif [ -f "${AGENT_HOME:-/opt/agent-app}/.env" ]; then
  # shellcheck disable=SC1091
  . "${AGENT_HOME:-/opt/agent-app}/.env"
fi

AGENT_HOME=${AGENT_HOME:-/opt/agent-app}
AGENT_PORT=${AGENT_PORT:-15034}
AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR:-$AGENT_HOME/upload_files}
AGENT_KEY_PATH=${AGENT_KEY_PATH:-$AGENT_HOME/api_keys/t_secret.key}
AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
LOG_FILE="$AGENT_LOG_DIR/monitor.log"
MAX_LOG_BYTES=$((10 * 1024 * 1024))
MAX_LOG_COUNT=10
MONITOR_SAMPLE_MODE=${MONITOR_SAMPLE_MODE:-0}

warn() {
  printf '[WARNING] %s\n' "$*"
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

ensure_log_dir() {
  [ -d "$AGENT_LOG_DIR" ] || mkdir -p "$AGENT_LOG_DIR" 2>/dev/null || fail "log directory is not writable: $AGENT_LOG_DIR"
  [ -w "$AGENT_LOG_DIR" ] || fail "log directory is not writable: $AGENT_LOG_DIR"
}

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return 0

  local size
  size=$(wc -c < "$LOG_FILE" 2>/dev/null || printf '0')
  [ "${size:-0}" -gt "$MAX_LOG_BYTES" ] || return 0

  local i
  i=$((MAX_LOG_COUNT - 1))
  while [ "$i" -ge 1 ]; do
    if [ -f "$LOG_FILE.$i" ]; then
      mv "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
    fi
    i=$((i - 1))
  done

  mv "$LOG_FILE" "$LOG_FILE.1"
  : > "$LOG_FILE"
}

find_agent_pid() {
  pgrep -f "$AGENT_HOME/agent_app.py|agent_app.py|agent-app" 2>/dev/null | head -n 1
}

check_port_listen() {
  ss -tulnp 2>/dev/null | awk -v port=":$AGENT_PORT" '
    $1 ~ /tcp/ && $0 ~ /LISTEN/ && index($0, port) > 0 { found=1 }
    END { exit found ? 0 : 1 }
  '
}

check_health() {
  if [ "$MONITOR_SAMPLE_MODE" = "1" ]; then
    printf '%s' "$$"
    return 0
  fi

  local pid
  pid=$(find_agent_pid)
  [ -n "$pid" ] || fail "agent_app.py process is not running"
  check_port_listen || fail "port $AGENT_PORT is not LISTEN"
  printf '%s' "$pid"
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    ufw status 2>/dev/null | grep -qi '^Status: active' && return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --state 2>/dev/null | grep -qi '^running$' && return 0
  fi

  warn "firewall is inactive or cannot be checked"
}

cpu_used_percent() {
  local a b
  if [ ! -r /proc/stat ]; then
    ps -A -o %cpu= 2>/dev/null | awk '{ sum += $1 } END { printf "%.1f", sum ? sum : 0 }'
    return 0
  fi

  a=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)
  sleep 1
  b=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)

  awk -v a="$a" -v b="$b" '
    BEGIN {
      split(a, x, " "); split(b, y, " ");
      idle1=x[4]+x[5]; idle2=y[4]+y[5];
      total1=0; total2=0;
      for (i=1; i<=7; i++) { total1+=x[i]; total2+=y[i]; }
      dt=total2-total1; di=idle2-idle1;
      if (dt <= 0) printf "0.0";
      else printf "%.1f", (100 * (dt - di) / dt);
    }
  '
}

mem_used_percent() {
  if command -v free >/dev/null 2>&1; then
    free | awk '/^Mem:/ { printf "%.1f", ($3 / $2) * 100 }'
    return 0
  fi

  if command -v vm_stat >/dev/null 2>&1; then
    vm_stat | awk '
      /page size of/ { gsub("\\.", "", $8); page_size=$8 }
      /Pages free/ { gsub("\\.", "", $3); free_pages=$3 }
      /Pages active/ { gsub("\\.", "", $3); active=$3 }
      /Pages inactive/ { gsub("\\.", "", $3); inactive=$3 }
      /Pages speculative/ { gsub("\\.", "", $3); speculative=$3 }
      /Pages wired down/ { gsub("\\.", "", $4); wired=$4 }
      /Pages occupied by compressor/ { gsub("\\.", "", $5); compressed=$5 }
      END {
        total=free_pages+active+inactive+speculative+wired+compressed
        used=active+wired+compressed
        if (total <= 0) printf "0.0"; else printf "%.1f", (used / total) * 100
      }
    '
    return 0
  fi

  printf '0.0'
}

disk_used_percent() {
  local target
  target=$AGENT_HOME
  [ -d "$target" ] || target=$AGENT_LOG_DIR
  [ -d "$target" ] || target=.

  df -P "$target" | awk 'NR==2 { gsub("%", "", $5); printf "%s", $5 }'
}

is_over_threshold() {
  awk -v value="$1" -v limit="$2" 'BEGIN { exit (value > limit) ? 0 : 1 }'
}

main() {
  ensure_log_dir
  rotate_log_if_needed

  local pid cpu mem disk timestamp
  pid=$(check_health)
  check_firewall

  cpu=$(cpu_used_percent)
  mem=$(mem_used_percent)
  disk=$(disk_used_percent)

  is_over_threshold "$cpu" 20 && warn "CPU usage is high: $cpu%"
  is_over_threshold "$mem" 10 && warn "MEM usage is high: $mem%"
  is_over_threshold "$disk" 80 && warn "DISK usage is high: $disk%"

  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' "$timestamp" "$pid" "$cpu" "$mem" "$disk" | tee -a "$LOG_FILE"
}

main "$@"
