# 필수 증거 체크리스트

아래 항목은 Ubuntu 22.04 LTS에서 `sudo bash scripts/setup_agent_env.sh --strict-firewall` 실행 후 확인합니다.

## SSH 20022 + Root 차단

```bash
sudo sshd -T | grep -E '^(port|permitrootlogin)'
ss -tulnp | grep ':20022'
```

예상:

```text
port 20022
permitrootlogin no
tcp LISTEN ... :20022 ...
```

## 방화벽 20022/15034 only

```bash
sudo ufw status numbered
```

예상:

```text
Status: active
20022/tcp ALLOW IN Anywhere
15034/tcp ALLOW IN Anywhere
```

## 계정/그룹

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

예상:

```text
agent-common: agent-admin,agent-dev,agent-test
agent-core: agent-admin,agent-dev
```

## 디렉터리 권한

```bash
ls -ld /opt/agent-app /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app
ls -l /opt/agent-app/api_keys/t_secret.key /opt/agent-app/bin/monitor.sh
```

예상:

```text
/opt/agent-app/upload_files -> root:agent-common, 2770
/opt/agent-app/api_keys -> root:agent-core, 2770
/var/log/agent-app -> root:agent-core, 2770
t_secret.key -> root:agent-core, 0640
monitor.sh -> agent-dev:agent-core, 0750
```

## 환경 변수

```bash
cat /etc/profile.d/agent-app.sh
sudo -u agent-dev bash -lc 'echo "$AGENT_HOME $AGENT_PORT $AGENT_UPLOAD_DIR $AGENT_KEY_PATH $AGENT_LOG_DIR"'
```

예상:

```text
/opt/agent-app 15034 /opt/agent-app/upload_files /opt/agent-app/api_keys/t_secret.key /var/log/agent-app
```

## Boot Sequence 5단계 OK

```bash
sudo -u agent-dev -E /opt/agent-app/agent_app.py
```

예상:

```text
Boot Sequence 1/5 OK
Boot Sequence 2/5 OK
Boot Sequence 3/5 OK
Boot Sequence 4/5 OK
Boot Sequence 5/5 OK
Agent READY
```

## 0.0.0.0:15034 LISTEN

```bash
ss -tulnp | grep ':15034'
```

예상:

```text
tcp LISTEN ... 0.0.0.0:15034 ...
```

## monitor.sh 결과

```bash
sudo -u agent-admin -E /opt/agent-app/bin/monitor.sh
echo $?
```

예상:

```text
[WARNING] MEM usage is high: 15.2%
[2026-05-24 10:00:00] PID:1234 CPU:3.1% MEM:15.2% DISK_USED:42%
0
```

CPU/MEM/DISK 임계값 초과 시 `[WARNING]`이 출력됩니다. 앱 프로세스 또는 15034 LISTEN 상태가 없으면 `[ERROR]` 후 종료 코드 1이 반환됩니다.

## /var/log/agent-app/monitor.log

```bash
sudo tail -n 5 /var/log/agent-app/monitor.log
```

예상:

```text
[2026-05-24 10:00:00] PID:1234 CPU:3.1% MEM:15.2% DISK_USED:42%
[2026-05-24 10:01:00] PID:1234 CPU:2.7% MEM:15.3% DISK_USED:42%
```

## crontab 매분 실행

```bash
sudo crontab -u agent-admin -l
sleep 120
sudo tail -n 3 /var/log/agent-app/monitor.log
```

예상:

```cron
* * * * * . /etc/profile.d/agent-app.sh; /opt/agent-app/bin/monitor.sh >/dev/null 2>&1
```

1~2분 뒤 `monitor.log`에 서로 다른 시각의 로그가 누적되어야 합니다.

## 보너스 report.sh

```bash
/opt/agent-app/bin/report.sh
```

예상:

```text
Metric Avg(%) Max(%) Min(%)
CPU    3.0   4.8   1.2
MEM    15.2  15.4  15.0
DISK   42.0  42.0  42.0
```
