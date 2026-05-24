#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

AGENT_HOME=${AGENT_HOME:-/opt/agent-app}
AGENT_PORT=${AGENT_PORT:-15034}
AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR:-$AGENT_HOME/upload_files}
AGENT_KEY_PATH=${AGENT_KEY_PATH:-$AGENT_HOME/api_keys/t_secret.key}
AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
STRICT_FIREWALL=0

if [ "${1:-}" = "--strict-firewall" ]; then
  STRICT_FIREWALL=1
fi

[ "$(id -u)" -eq 0 ] || {
  printf 'Run with sudo: sudo %s [--strict-firewall]\n' "$0" >&2
  exit 1
}

repo_root=$(cd "$(dirname "$0")/.." && pwd)

create_groups_and_users() {
  groupadd -f agent-common
  groupadd -f agent-core

  for user in agent-admin agent-dev agent-test; do
    if ! id "$user" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$user"
    fi
  done

  usermod -aG agent-common,agent-core agent-admin
  usermod -aG agent-common,agent-core agent-dev
  usermod -aG agent-common agent-test
}

install_files() {
  install -d -o root -g agent-common -m 2775 "$AGENT_HOME"
  install -d -o root -g agent-common -m 2770 "$AGENT_UPLOAD_DIR"
  install -d -o root -g agent-core -m 2770 "$(dirname "$AGENT_KEY_PATH")"
  install -d -o root -g agent-core -m 2770 "$AGENT_LOG_DIR"
  install -d -o root -g agent-core -m 2750 "$AGENT_HOME/bin"

  printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH"
  chown root:agent-core "$AGENT_KEY_PATH"
  chmod 0640 "$AGENT_KEY_PATH"

  install -o agent-dev -g agent-core -m 0750 "$repo_root/scripts/monitor.sh" "$AGENT_HOME/bin/monitor.sh"
  install -o agent-dev -g agent-core -m 0750 "$repo_root/scripts/report.sh" "$AGENT_HOME/bin/report.sh"

  if [ -f "$repo_root/resources/agent-app" ]; then
    install -o agent-dev -g agent-core -m 0750 "$repo_root/resources/agent-app" "$AGENT_HOME/agent_app.py"
  fi

  cat > "$AGENT_HOME/.env" <<EOF
export AGENT_HOME=$AGENT_HOME
export AGENT_PORT=$AGENT_PORT
export AGENT_UPLOAD_DIR=$AGENT_UPLOAD_DIR
export AGENT_KEY_PATH=$AGENT_KEY_PATH
export AGENT_LOG_DIR=$AGENT_LOG_DIR
EOF
  chown root:agent-common "$AGENT_HOME/.env"
  chmod 0644 "$AGENT_HOME/.env"

  install -o root -g root -m 0644 "$AGENT_HOME/.env" /etc/profile.d/agent-app.sh

  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m g:agent-common:rwx -m d:g:agent-common:rwx "$AGENT_UPLOAD_DIR"
    setfacl -m g:agent-core:rwx -m d:g:agent-core:rwx "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR"
  fi
}

configure_sshd() {
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/99-agent-app.conf <<EOF
Port 20022
PermitRootLogin no
EOF

  if command -v sshd >/dev/null 2>&1; then
    sshd -t
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
    systemctl restart ssh
  elif systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
    systemctl restart sshd
  fi
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if [ "$STRICT_FIREWALL" -eq 1 ]; then
      ufw --force reset
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 20022/tcp
    ufw allow "$AGENT_PORT/tcp"
    ufw --force enable
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl enable --now firewalld
    if [ "$STRICT_FIREWALL" -eq 1 ]; then
      firewall-cmd --permanent --remove-service=ssh || true
    fi
    firewall-cmd --permanent --add-port=20022/tcp
    firewall-cmd --permanent --add-port="$AGENT_PORT/tcp"
    firewall-cmd --reload
    return 0
  fi

  printf '[WARNING] ufw/firewalld not found. Install one firewall package.\n' >&2
}

install_cron() {
  local tmp
  tmp=$(mktemp)
  crontab -u agent-admin -l > "$tmp" 2>/dev/null || true
  grep -v "$AGENT_HOME/bin/monitor.sh" "$tmp" > "$tmp.new" || true
  printf '* * * * * . /etc/profile.d/agent-app.sh; %s/bin/monitor.sh >/dev/null 2>&1\n' "$AGENT_HOME" >> "$tmp.new"
  crontab -u agent-admin "$tmp.new"
  rm -f "$tmp" "$tmp.new"
}

main() {
  create_groups_and_users
  install_files
  configure_sshd
  configure_firewall
  install_cron

  printf 'Setup complete.\n'
  printf 'AGENT_HOME=%s\n' "$AGENT_HOME"
  printf 'Run app as: sudo -u agent-dev -E %s/agent_app.py\n' "$AGENT_HOME"
  printf 'Check SSH: ss -tulnp | grep 20022\n'
  printf 'Check app: ss -tulnp | grep %s\n' "$AGENT_PORT"
  printf 'Check cron: crontab -u agent-admin -l\n'
}

main "$@"
