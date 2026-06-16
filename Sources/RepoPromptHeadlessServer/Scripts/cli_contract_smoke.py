#!/usr/bin/env python3
"""Black-box smoke test for rpce-headless CLI agent-ergonomics contract."""
import argparse
import json
import subprocess
import sys

parser = argparse.ArgumentParser(description="Smoke-test rpce-headless CLI help, JSON, and robot docs.")
parser.add_argument("binary")
parser.add_argument("root")
args = parser.parse_args()


def run(command, expected_code=0):
    result = subprocess.run(
        [args.binary, *command],
        cwd=args.root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == expected_code, (command, result.returncode, result.stdout, result.stderr)
    return result


help_commands = [
    ["--help"],
    ["-h"],
    ["serve", "--help"],
    ["dump", "--help"],
    ["connect", "--help"],
    ["context-build", "--help"],
    ["capabilities", "--help"],
    ["robot-docs", "--help"],
]

for command in help_commands:
    result = run(command)
    assert "Usage: rpce-headless" in result.stdout, (command, result.stdout)
    assert result.stderr == "", (command, result.stderr)

capabilities = run(["capabilities", "--json"])
payload = json.loads(capabilities.stdout)
assert payload["tool_name"] == "rpce-headless", payload
assert payload["contract_version"], payload
assert args.root in payload["loaded_roots"], payload
assert any(t["name"] == "stdio" and "context_builder" in t["tools"] for t in payload["transports"]), payload
assert any(t["name"] == "socket" and "headless_capabilities" in t["tools"] for t in payload["transports"]), payload
assert capabilities.stderr == "", capabilities.stderr

dump = run(["dump", "--json"])
dump_payload = json.loads(dump.stdout)
assert args.root in dump_payload["loaded_roots"], dump_payload
assert dump_payload["root_count"] >= 1, dump_payload
assert dump.stderr == "", dump.stderr

robot_docs = run(["robot-docs", "guide"])
for fragment in ["capabilities --json", "headless_capabilities", "context_builder", "agent_manage", "agent_run"]:
    assert fragment in robot_docs.stdout, (fragment, robot_docs.stdout[:1000])
assert robot_docs.stderr == "", robot_docs.stderr

typo = run(["dump", "--jsno"], expected_code=64)
assert "Did you mean `--json`?" in typo.stderr, typo.stderr
assert typo.stdout == "", typo.stdout

print("CLI CONTRACT OK")
