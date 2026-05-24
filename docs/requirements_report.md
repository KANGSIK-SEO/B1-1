# 요구사항 수행 내역서

## 1. SSH 보안 설정

- 설정 파일: `/etc/ssh/sshd_config.d/99-agent-app.conf`
- 적용 내용:

```text
Port 20022
PermitRootLogin no
```

- 검증 명령:

```bash
sudo sshd -t
sudo systemctl restart ssh
ss -tulnp | grep ':20022'
sudo sshd -T | grep -E '^(port|permitrootlogin)'
```

SSH 기본 포트 22 대신 20022를 사용하면 무작위 스캔과 자동 공격 노출을 줄일 수 있습니다. `PermitRootLogin no`는 root 계정 원격 직접 로그인을 막아, 개인 계정 로그인 후 필요한 작업만 `sudo`로 수행하게 만드는 계정 추적성과 최소 권한 원칙을 강화합니다.

## 2. 방화벽 설정

- 사용 도구: UFW 우선, 없으면 firewalld
- 허용 포트: TCP 20022, TCP 15034
- 기본 정책: incoming deny, outgoing allow
- 엄격 적용:

```bash
sudo bash scripts/setup_agent_env.sh --strict-firewall
```

- 검증 명령:

```bash
sudo ufw status numbered
sudo ss -tulnp | grep -E ':(20022|15034)'
```

운영 서버의 외부 노출면을 SSH 관리 포트와 앱 포트로 제한하여 불필요한 서비스 접근을 차단합니다.

## 3. 계정/그룹/ACL

- 계정:
  - `agent-admin`
  - `agent-dev`
  - `agent-test`
- 그룹:
  - `agent-common`: `agent-admin`, `agent-dev`, `agent-test`
  - `agent-core`: `agent-admin`, `agent-dev`

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

역할별 그룹을 분리해 공통 업로드 영역은 모든 역할이 쓰되, API 키와 운영 로그는 admin/dev만 접근하도록 했습니다.

## 4. 디렉터리/권한

- `$AGENT_HOME`: `/opt/agent-app`, `root:agent-common`, `2775`
- `$AGENT_UPLOAD_DIR`: `/opt/agent-app/upload_files`, `root:agent-common`, `2770`
- `$AGENT_HOME/api_keys`: `root:agent-core`, `2770`
- `$AGENT_LOG_DIR`: `/var/log/agent-app`, `root:agent-core`, `2770`
- `$AGENT_KEY_PATH`: `/opt/agent-app/api_keys/t_secret.key`, `root:agent-core`, `0640`
- `$AGENT_HOME/bin/monitor.sh`: `agent-dev:agent-core`, `0750`

검증 명령:

```bash
ls -ld /opt/agent-app /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app
ls -l /opt/agent-app/api_keys/t_secret.key /opt/agent-app/bin/monitor.sh
getfacl /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app
```

`upload_files`는 `agent-common`에 읽기/쓰기 권한을 주고, `api_keys`와 `/var/log/agent-app`는 `agent-core` 전용으로 제한합니다.

## 5. 환경 변수

- 등록 위치:
  - `/etc/profile.d/agent-app.sh`
  - `/opt/agent-app/.env`
- 값:

```bash
export AGENT_HOME=/opt/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=/opt/agent-app/upload_files
export AGENT_KEY_PATH=/opt/agent-app/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
```

환경 변수로 실행 경로, 포트, 키 경로, 로그 경로를 고정하면 사용자별 셸 환경 차이로 인한 실행 실패를 줄일 수 있습니다.

## 6. 앱 실행 환경

- 실행 사용자: `agent-dev`
- 설치 파일: `/opt/agent-app/agent_app.py`
- API 키 내용:

```text
agent_api_key_test
```

- 실행 예:

```bash
sudo -u agent-dev -E /opt/agent-app/agent_app.py
```

- 검증 예:

```bash
pgrep -af 'agent_app.py|agent-app'
ss -tulnp | grep ':15034'
```

정상 실행 시 Boot Sequence 5단계가 모두 OK로 출력되고, `Agent READY`, `0.0.0.0:15034 LISTEN` 상태가 확인되어야 합니다.

## 7. monitor.sh

- 경로: `/opt/agent-app/bin/monitor.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `0750`
- Health Check:
  - `agent_app.py` 프로세스 실행 여부
  - TCP 15034 LISTEN 여부
  - 비정상 시 `[ERROR]` 출력 후 `exit 1`
- 방화벽 상태:
  - UFW active 또는 firewalld running 확인
  - 비활성 시 `[WARNING]` 출력, 스크립트는 계속 실행
- 수집 항목:
  - CPU Used %
  - MEM Used %
  - DISK Used %
- 임계값:
  - CPU > 20%
  - MEM > 10%
  - DISK > 80%
- 로그 형식:

```text
[YYYY-MM-DD HH:MM:SS] PID:1234 CPU:3.1% MEM:15.2% DISK_USED:42%
```

- 로그 경로: `/var/log/agent-app/monitor.log`
- 로그 보존: 스크립트 자체 회전, 10MB 초과 시 `monitor.log.1`로 이동, 최대 10개 보존

## 8. cron 등록

- 등록 사용자: `agent-admin`
- 실행 주기: 매분

```cron
* * * * * . /etc/profile.d/agent-app.sh; /opt/agent-app/bin/monitor.sh >/dev/null 2>&1
```

- 검증:

```bash
sudo crontab -u agent-admin -l
sleep 120
sudo tail -n 5 /var/log/agent-app/monitor.log
```

`agent-admin`은 `agent-core` 그룹에 포함되어 있어 `/var/log/agent-app/monitor.log`에 기록할 수 있습니다.

## 9. 보너스 report.sh

- 경로: `/opt/agent-app/bin/report.sh`
- 기능:
  - CPU/MEM/DISK 평균, 최대, 최소 계산
  - `-s`, `-e` 옵션으로 시간 구간 필터링

```bash
/opt/agent-app/bin/report.sh
/opt/agent-app/bin/report.sh -s "2026-05-24 09:00:00" -e "2026-05-24 18:00:00"
```
