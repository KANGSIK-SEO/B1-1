# ShellTool 확장 보고서

## 핵심 판단

과제의 필수 제출물은 Bash 기반 `monitor.sh`입니다.

LangChain `ShellTool`은 필수 구현을 대체하지 않고, 쉘 명령을 읽기 어려운 사용자를 위한 운영 보조 기능으로만 사용했습니다.

## 왜 ShellTool을 붙였는가

리눅스 관제에서는 다음 명령을 자주 사용합니다.

```bash
ps -ef | grep agent-app
ss -tulnp | grep 15034
tail -n 20 /var/log/agent-app/monitor.log
```

초보자는 이 명령 자체와 출력 해석이 어렵습니다.

ShellTool을 사용하면 프로그램이 명령을 대신 실행하고, 이후 AI Agent와 연결했을 때 결과를 한국어로 설명할 수 있습니다.

## 실행 계정

ShellTool은 `agent-dev` 계정에서 실행합니다.

이유:

- `agent-dev`는 `agent-app` 실행 주체입니다.
- `monitor.sh` 수동 점검 권한을 갖습니다.
- `/var/log/agent-app` 조회가 가능합니다.
- `agent-admin`은 cron 운영 역할로 분리합니다.

## 실행 예시

```bash
. /opt/agent-app/.env
python3 shelltool/shelltool_demo.py
```

출력 예시:

```text
$ ps -ef | grep '[a]gent-app'
agent-dev ... /opt/agent-app/bin/agent-app

$ ss -tulnp | grep ':15034' || true
tcp LISTEN 0 1 0.0.0.0:15034 ...

$ /opt/agent-app/bin/monitor.sh; echo monitor_exit:$?
[INFO] PID:99 CPU:0.1% MEM:0.0% DISK_USED:2%
monitor_exit:0
```

## 보안 주의

ShellTool은 쉘 명령을 실행할 수 있으므로 실제 회사 서버에서는 제한이 필요합니다.

권장 정책:

- root 실행 금지
- sudo 금지 또는 allowlist 제한
- 조회 명령만 허용
- 실행 명령 로그 기록
- 재시작/삭제/권한 변경 명령은 사람 승인 후 실행

허용 예시:

```text
ps, ss, df, free, top, tail, grep, journalctl
```

차단 예시:

```text
rm, kill, shutdown, reboot, chmod 777, curl | bash
```

## 결론

ShellTool은 관제 스크립트가 아니라, AI가 리눅스 명령을 대신 실행하고 결과를 해석하기 위한 보조 도구입니다.

이 제출물에서는 Bash `monitor.sh`를 핵심으로 유지하고, ShellTool은 선택 확장 기능으로 분리했습니다.
