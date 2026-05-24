#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
sample_log_dir="$repo_root/logs/var/log/agent-app"
sample_log_file="$sample_log_dir/monitor.log"

mkdir -p "$sample_log_dir"
: > "$sample_log_file"

for _ in 1 2 3; do
  AGENT_HOME="$repo_root" \
  AGENT_LOG_DIR="$sample_log_dir" \
  AGENT_PORT=15034 \
  MONITOR_SAMPLE_MODE=1 \
    "$repo_root/scripts/monitor.sh" >/dev/null
  sleep 1
done

printf 'sample log generated: %s\n' "$sample_log_file"
tail -n 3 "$sample_log_file"
