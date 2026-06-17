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
assert any(r["path"] == args.root and r["name"] for r in payload["loaded_root_metadata"]), payload
assert "headless_status" in payload["recommended_workflow"][0], payload
assert "robot-docs status --json" in payload["recommended_workflow"][0], payload
assert "headless_capabilities" in payload["recommended_workflow"][1], payload
assert "fuller contract" in payload["recommended_workflow"][1], payload
assert payload["architecture_onboarding"]["preferred_summary_tool"] == "context_builder", payload
assert payload["native_workflows"]["source"].startswith("RepoPrompt CE native"), payload
assert {r["name"] for r in payload["native_workflows"]["roles"]} >= {"explore", "engineer", "pair", "design"}, payload
assert {w["name"] for w in payload["native_workflows"]["workflows"]} >= {"investigate", "optimize", "deep_plan"}, payload
assert payload["native_workflows"]["custom_workflows"]["current_headless_support"] == "metadata_only", payload
assert any("workflow_name" in item for item in payload["native_workflows"]["custom_workflows"]["future_headless_contract"]), payload
assert "original result shape" in payload["context_builder"]["sync_example"], payload
assert "running lifecycle snapshot" in payload["context_builder"]["timeout_guidance"], payload
assert "RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS" in payload["context_builder"]["timeout_guidance"], payload
assert any(t["name"] == "stdio" and "context_builder" in t["tools"] for t in payload["transports"]), payload
assert any(t["name"] == "socket" and "headless_status" in t["tools"] for t in payload["transports"]), payload
assert capabilities.stderr == "", capabilities.stderr

status = run(["robot-docs", "status", "--json"])
status_payload = json.loads(status.stdout)
assert status_payload["tool_name"] == "rpce-headless", status_payload
assert status_payload["status"] in ("ready", "needs_attention"), status_payload
assert args.root in status_payload["loaded_roots"], status_payload
assert any(r["path"] == args.root for r in status_payload["loaded_root_metadata"]), status_payload
assert status_payload["suggested_first_tool_calls"][0] == "headless_status", status_payload
assert "context_builder" in status_payload["suggested_first_tool_calls"][1], status_payload
assert status_payload["available_agent_tools"]["context_builder"], status_payload
assert status_payload["architecture_onboarding"]["preferred_summary_tool"] == "context_builder", status_payload
assert status_payload["native_workflows"]["distinction"].startswith("These are composition patterns"), status_payload
assert status_payload["native_workflows"]["custom_workflows"]["current_headless_support"] == "metadata_only", status_payload
assert status.stderr == "", status.stderr

dump = run(["dump", "--json"])
dump_payload = json.loads(dump.stdout)
assert args.root in dump_payload["loaded_roots"], dump_payload
assert any(r["path"] == args.root and "current_directory_relationship" in r for r in dump_payload["loaded_root_metadata"]), dump_payload
assert dump_payload["root_count"] >= 1, dump_payload
assert dump.stderr == "", dump.stderr

robot_docs = run(["robot-docs", "guide"])
for fragment in ["robot-docs status --json", "headless_status", "capabilities --json", "headless_capabilities", "context_builder", "agent_manage", "agent_run"]:
    assert fragment in robot_docs.stdout, (fragment, robot_docs.stdout[:1000])
for fragment in ["Native RepoPrompt workflow shapes", "Investigate", "Optimize", "Deep Plan", "Custom workflows"]:
    assert fragment in robot_docs.stdout, (fragment, robot_docs.stdout[:1000])
for fragment in ["original result shape", "running lifecycle snapshot"]:
    assert fragment in robot_docs.stdout, (fragment, robot_docs.stdout[:1000])
assert robot_docs.stderr == "", robot_docs.stderr

typo = run(["dump", "--jsno"], expected_code=64)
assert "Did you mean `--json`?" in typo.stderr, typo.stderr
assert typo.stdout == "", typo.stdout

print("CLI CONTRACT OK")
