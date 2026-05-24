#!/usr/bin/env bash
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -f /etc/profile.d/agent-app.sh ]; then
  # shellcheck disable=SC1091
  . /etc/profile.d/agent-app.sh
fi

AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
LOG_FILE=${LOG_FILE:-$AGENT_LOG_DIR/monitor.log}
START_TIME=
END_TIME=

usage() {
  cat <<'USAGE'
Usage: report.sh [-f LOG_FILE] [-s "YYYY-MM-DD HH:MM:SS"] [-e "YYYY-MM-DD HH:MM:SS"]

Shows CPU/MEM/DISK average, maximum, and minimum from monitor.log.
USAGE
}

while getopts ':f:s:e:h' opt; do
  case "$opt" in
    f) LOG_FILE=$OPTARG ;;
    s) START_TIME=$OPTARG ;;
    e) END_TIME=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -r "$LOG_FILE" ] || {
  printf '[ERROR] log file is not readable: %s\n' "$LOG_FILE" >&2
  exit 1
}

awk -v start="$START_TIME" -v end="$END_TIME" '
  function value_of(name, line, arr, regex) {
    regex=name ":[0-9.]+%"
    if (match(line, regex)) {
      split(substr(line, RSTART, RLENGTH), arr, /[:%]/)
      return arr[2] + 0
    }
    return ""
  }

  function add(metric, value) {
    count[metric]++
    sum[metric] += value
    if (count[metric] == 1 || value > max[metric]) max[metric] = value
    if (count[metric] == 1 || value < min[metric]) min[metric] = value
  }

  /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
    ts=substr($0, 2, 19)
    if (start != "" && ts < start) next
    if (end != "" && ts > end) next

    cpu=value_of("CPU", $0)
    mem=value_of("MEM", $0)
    disk=value_of("DISK_USED", $0)

    if (cpu != "") add("CPU", cpu)
    if (mem != "") add("MEM", mem)
    if (disk != "") add("DISK", disk)
  }

  END {
    if (count["CPU"] == 0) {
      print "No monitor samples found."
      exit 1
    }

    printf "Metric Avg(%%) Max(%%) Min(%%)\n"
    printf "CPU    %.1f   %.1f   %.1f\n", sum["CPU"]/count["CPU"], max["CPU"], min["CPU"]
    printf "MEM    %.1f   %.1f   %.1f\n", sum["MEM"]/count["MEM"], max["MEM"], min["MEM"]
    printf "DISK   %.1f   %.1f   %.1f\n", sum["DISK"]/count["DISK"], max["DISK"], min["DISK"]
  }
' "$LOG_FILE"
