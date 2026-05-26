from __future__ import annotations

import os
import platform
import sys
from pathlib import Path


COMMANDS = [
    "id",
    "ps -ef | grep '[a]gent-app'",
    "ss -tulnp | grep ':15034' || true",
    "/opt/agent-app/bin/monitor.sh; echo monitor_exit:$?",
    "tail -n 20 /var/log/agent-app/monitor.log",
]


def running_in_linux_agent_env() -> bool:
    return (
        platform.system() == "Linux"
        and Path("/opt/agent-app").exists()
        and Path("/var/log/agent-app").exists()
    )


def print_usage() -> None:
    print("ShellTool demo must run inside the Linux agent environment.")
    print()
    print("Expected environment:")
    print("  user: agent-dev")
    print("  app: /opt/agent-app/bin/agent-app")
    print("  monitor: /opt/agent-app/bin/monitor.sh")
    print("  log: /var/log/agent-app/monitor.log")
    print()
    print("Run inside Ubuntu:")
    print("  . /opt/agent-app/.env")
    print("  python3 shelltool/shelltool_demo.py")


def main() -> None:
    if not running_in_linux_agent_env():
        print_usage()
        sys.exit(2)

    try:
        from langchain_community.tools import ShellTool
    except ModuleNotFoundError as exc:
        missing = exc.name or "langchain_community"
        print(f"Missing Python package: {missing}")
        print("Install dependencies:")
        print("  python3 -m pip install -r shelltool/requirements.txt")
        sys.exit(1)

    os.environ.setdefault("LANGCHAIN_TRACING_V2", "false")
    shell = ShellTool()

    for command in COMMANDS:
        print(f"\n$ {command}")
        print(shell.run(command))


if __name__ == "__main__":
    main()
