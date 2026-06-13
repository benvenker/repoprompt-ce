#!/usr/bin/env python3
"""Black-box smoke test for headless process-backed agent MCP tools."""
import argparse
import itertools
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

FAKE_AGENT = r'''
#!/usr/bin/env python3
import itertools, json, os, subprocess, sys

sentinel = "RPCE_AGENT_SMOKE_SENTINEL"
prompt = os.environ.get("RPCE_DISCOVER_PROMPT", "")
print(f"{sentinel}:{prompt}", flush=True)

config_path = sys.argv[1]
with open(config_path) as f:
    cfg = json.load(f)
server = cfg["mcpServers"]["repoprompt"]
p = subprocess.Popen([server["command"], *server.get("args", [])], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
ids = itertools.count(1)

def rpc(method, params=None):
    i = next(ids)
    p.stdin.write(json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params or {}})+"\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            err = p.stderr.read()
            raise SystemExit(f"server closed stdout while waiting for {method}; stderr={err}")
        msg = json.loads(line)
        if msg.get("id") == i:
            if "error" in msg:
                raise SystemExit(f"{method} returned error: {msg['error']}")
            return msg["result"]

def notify(method, params=None):
    p.stdin.write(json.dumps({"jsonrpc":"2.0","method":method,"params":params or {}})+"\n")
    p.stdin.flush()

rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"fake-agent-runner","version":"0"}})
notify("notifications/initialized")
tools = {t["name"] for t in rpc("tools/list")["tools"]}
assert "agent_run" not in tools, tools
assert "agent_manage" not in tools, tools
assert "agent_explore" not in tools, tools
blocked = rpc("tools/call", {"name":"agent_run", "arguments":{"op":"poll", "session_id":"blocked"}})
blocked_text = "".join(c.get("text", "") for c in blocked.get("content", []))
assert blocked.get("isError"), blocked_text
assert "discovery-restricted" in blocked_text, blocked_text
p.stdin.close()
p.wait(timeout=10)
'''


def write_file(path, content, mode=None):
    path.write_text(content)
    if mode is not None:
        path.chmod(mode)


def start_server(binary, root, fake_agent, agent_config):
    env = dict(os.environ)
    env["FAKE_AGENT_SCRIPT"] = str(fake_agent)
    env["RPCE_AGENT_CONFIG"] = str(agent_config)
    env["RPCE_AGENT_RUN_DEFAULT_AGENT"] = "fake"
    env["HOME"] = tempfile.mkdtemp(prefix="rpce-headless-agent-home-")
    env["CFFIXED_USER_HOME"] = env["HOME"]
    return subprocess.Popen(
        [binary, "serve", "--root", str(root)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def main():
    parser = argparse.ArgumentParser(description="Smoke-test headless agent_run/agent_manage over MCP stdio.")
    parser.add_argument("binary")
    parser.add_argument("root", nargs="?", help="Workspace root. Defaults to a temporary workspace.")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="rpce-headless-agent-smoke-") as tmp:
        tmp_path = Path(tmp)
        root = Path(args.root) if args.root else tmp_path / "workspace"
        root.mkdir(parents=True, exist_ok=True)
        (root / "smoke.txt").write_text("hello headless agent smoke\n")

        fake_agent = tmp_path / "fake_agent.py"
        write_file(fake_agent, FAKE_AGENT, 0o700)
        agent_config = tmp_path / "agents.json"
        write_file(agent_config, json.dumps({
            "fake": {
                "argv": ["python3", "{FAKE_AGENT_SCRIPT}", "{MCP_CONFIG_PATH_RAW}"],
                "promptVia": "env",
            }
        }))

        p = start_server(args.binary, root, fake_agent, agent_config)
        ids = itertools.count(1)

        def rpc(method, params=None):
            i = next(ids)
            p.stdin.write(json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params or {}})+"\n")
            p.stdin.flush()
            while True:
                line = p.stdout.readline()
                if not line:
                    err = p.stderr.read()
                    raise AssertionError(f"server closed stdout while waiting for {method}; stderr={err}")
                msg = json.loads(line)
                if msg.get("id") == i:
                    assert "error" not in msg, f"{method} -> {msg['error']}"
                    return msg["result"]

        def notify(method, params=None):
            p.stdin.write(json.dumps({"jsonrpc":"2.0","method":method,"params":params or {}})+"\n")
            p.stdin.flush()

        def call(name, arguments=None):
            result = rpc("tools/call", {"name": name, "arguments": arguments or {}})
            text = "".join(c.get("text", "") for c in result.get("content", []))
            return result, text

        def payload(result, text):
            if result.get("structuredContent") is not None:
                return result["structuredContent"]
            return json.loads(text)

        try:
            rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"agent-smoke-harness","version":"0"}})
            notify("notifications/initialized")
            tools = {t["name"] for t in rpc("tools/list")["tools"]}
            expected = {"agent_run", "agent_manage"}
            assert expected <= tools, f"missing: {expected - tools}; tools={sorted(tools)}"
            assert "agent_explore" not in tools, tools

            agents_result, agents_text = call("agent_manage", {"op": "list_agents"})
            agents_payload = payload(agents_result, agents_text)
            agent_names = {agent.get("name") for agent in agents_payload.get("agents", [])}
            assert "fake" in agent_names, agents_payload

            message = "hello from headless agent_run smoke"
            run_result, run_text = call("agent_run", {"op": "start", "model_id": "fake", "message": message, "detach": False, "timeout": 10})
            run_payload = payload(run_result, run_text)
            session_id = run_payload.get("session_id") or run_payload.get("session", {}).get("id")
            assert session_id, run_payload
            assert run_payload.get("status") == "completed", run_payload
            assert "RPCE_AGENT_SMOKE_SENTINEL" in json.dumps(run_payload), run_payload
            assert message in json.dumps(run_payload), run_payload

            sessions_result, sessions_text = call("agent_manage", {"op": "list_sessions"})
            sessions_payload = payload(sessions_result, sessions_text)
            assert any(session.get("session_id") == session_id for session in sessions_payload.get("sessions", [])), sessions_payload

            log_result, log_text = call("agent_manage", {"op": "get_log", "session_id": session_id})
            log_payload = payload(log_result, log_text)
            assert "RPCE_AGENT_SMOKE_SENTINEL" in json.dumps(log_payload), log_payload

            cleanup_result, cleanup_text = call("agent_manage", {"op": "cleanup_sessions", "session_ids": [session_id]})
            cleanup_payload = payload(cleanup_result, cleanup_text)
            assert cleanup_payload.get("deleted_count") == 1, cleanup_payload
            print("AGENT MCP SMOKE OK")
        finally:
            try:
                p.stdin.close()
            except Exception:
                pass
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=10)


if __name__ == "__main__":
    main()
