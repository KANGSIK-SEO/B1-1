# 문제 13: 시스템 관제 자동화 스크립트

Ubuntu 22.04 LTS 기준으로 SSH 보안, 방화벽, 계정/그룹/ACL, 실행 환경 변수, 관제 스크립트, cron 등록을 자동화한 제출물입니다.

## 구성

```text
.
├── docs/requirements_report.md
├── docs/evidence_checklist.md
├── docs/shelltool_report.md
├── resources/agent-app
├── shelltool
│   ├── README.md
│   ├── requirements.txt
│   └── shelltool_demo.py
└── scripts
    ├── monitor.sh
    ├── report.sh
    └── setup_agent_env.sh
```

## 설치

```bash
sudo bash scripts/setup_agent_env.sh --strict-firewall
```

`--strict-firewall` 옵션은 기존 UFW 규칙을 초기화하고 TCP 20022, 15034만 허용합니다. 기존 서버에서 실행할 때는 SSH 접속이 끊기지 않도록 콘솔 또는 별도 접근 경로를 확보한 뒤 실행해야 합니다.

## 앱 실행

```bash
sudo -u agent-dev -E /opt/agent-app/agent_app.py
```

제공된 `resources/agent-app` Linux 실행 파일은 설치 시 `/opt/agent-app/agent_app.py`로 배치됩니다. 프로세스명과 과제 요구사항의 `agent_app.py` 점검 조건을 맞추기 위한 설치 경로입니다.

## 관제 실행

```bash
sudo -u agent-admin -E /opt/agent-app/bin/monitor.sh
tail -f /var/log/agent-app/monitor.log
```

cron은 `agent-admin` 사용자에 매분 실행되도록 자동 등록됩니다.

```bash
sudo crontab -u agent-admin -l
```

## 로컬 증거 로그 생성

macOS나 개발 PC처럼 실제 Ubuntu 서버가 아닌 곳에서는 `/var/log/agent-app/monitor.log`를 만들 수 없거나 `ss`, UFW, `/proc/stat`이 없어 Health Check가 실패할 수 있습니다. 저장소 검토용 로그는 아래 명령으로 생성합니다.

```bash
bash scripts/generate_sample_log.sh
cat logs/var/log/agent-app/monitor.log
```

이 샘플 모드는 `MONITOR_SAMPLE_MODE=1`일 때만 앱 프로세스/포트 검사를 우회합니다. Ubuntu 제출 환경에서 기본 실행할 때는 여전히 `agent_app.py` 실행과 `15034 LISTEN`을 검사합니다.

## 보너스 리포트

```bash
/opt/agent-app/bin/report.sh
/opt/agent-app/bin/report.sh -s "2026-05-24 09:00:00" -e "2026-05-24 18:00:00"
```

## ShellTool 확장

`shelltool/` 폴더는 Bash 제출물을 대체하지 않는 선택 확장입니다.

LangChain `ShellTool`로 `ps`, `ss`, `tail`, `monitor.sh`를 대신 실행해 쉘 명령에 익숙하지 않은 사용자가 상태 확인 과정을 따라갈 수 있게 했습니다.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r shelltool/requirements.txt

. /opt/agent-app/.env
python3 shelltool/shelltool_demo.py
```

상세 설명은 `docs/shelltool_report.md`를 확인합니다.
