# ShellTool 운영 보조 데모

이 폴더는 Bash 기반 제출물(`scripts/monitor.sh`)을 대체하지 않습니다.

목적은 LangChain `ShellTool`로 리눅스 명령을 실행하고, 쉘 명령에 익숙하지 않은 사용자가 프로세스/포트/로그 상태를 쉽게 확인하도록 보조하는 것입니다.

## 역할 구분

```text
scripts/monitor.sh
  실제 관제 스크립트
  Bash로 작성
  cron으로 매분 실행
  /var/log/agent-app/monitor.log 기록

shelltool/shelltool_demo.py
  보조 시연 파일
  Python + LangChain ShellTool
  ps, ss, tail, monitor.sh를 대신 실행
```

## 실행 위치

ShellTool은 `agent-dev` 계정에서 실행합니다.

```text
agent-dev
  agent-app 실행
  monitor.sh 수동 점검
  ShellTool 보조 진단 실행

agent-admin
  cron 등록 및 운영 관리

agent-test
  권한 검증용
```

## 설치

Ubuntu 환경에서:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r shelltool/requirements.txt
```

## 실행

```bash
. /opt/agent-app/.env
python3 shelltool/shelltool_demo.py
```

Docker 데모 컨테이너 안이라면:

```bash
. /opt/agent-app/.env
python3 /opt/agent-app/bin/shelltool_demo.py
```

## ShellTool이 하는 일

아래 명령을 사용자가 직접 외우지 않아도 되도록, 프로그램이 순서대로 실행합니다.

```bash
id
ps -ef | grep '[a]gent-app'
ss -tulnp | grep ':15034' || true
/opt/agent-app/bin/monitor.sh
tail -n 20 /var/log/agent-app/monitor.log
```

## 주의

ShellTool은 기본적으로 쉘 명령 실행 권한이 강합니다.

회사나 실제 서버에서는 반드시 다음 원칙을 지켜야 합니다.

- root로 실행하지 않기
- `agent-dev` 같은 일반 계정 사용
- `rm`, `kill`, `chmod 777`, `sudo` 같은 위험 명령 제한
- 실행 명령 로그 남기기
- 재시작/삭제/권한 변경은 사람 승인 후 실행

