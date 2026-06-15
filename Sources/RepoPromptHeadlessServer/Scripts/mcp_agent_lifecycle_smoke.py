#!/usr/bin/env python3
"""Behavioral smoke test for headless process-backed agent lifecycle tools."""
import argparse
import itertools
import json
import os
import re
import subprocess
import sys
import tempfile
import time
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

SLEEPING_AGENT = r'''
#!/usr/bin/env python3
import os, subprocess, sys, time
sys.stdout.write("LIFECYCLE_AGENT_STARTED\n"); sys.stdout.flush()
sys.stdout.write(f"LIFECYCLE_AGENT_PID:{os.getpid()}\n"); sys.stdout.flush()
child = None
if os.environ.get("FAKE_AGENT_SPAWN_CHILD") == "1":
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])
    sys.stdout.write(f"LIFECYCLE_CHILD_PID:{child.pid}\n"); sys.stdout.flush()
time.sleep(float(os.environ.get("FAKE_AGENT_SLEEP", "600")))
'''


def write_file(path, content, mode=None):
    path.write_text(content)
    if mode is not None:
        path.chmod(mode)


def start_server(binary, root, fake_agent, agent_config, extra_env=None):
    env = dict(os.environ)
    env["FAKE_AGENT_SCRIPT"] = str(fake_agent)
    env["RPCE_AGENT_CONFIG"] = str(agent_config)
    env["RPCE_AGENT_RUN_DEFAULT_AGENT"] = "fake"
    env["HOME"] = tempfile.mkdtemp(prefix="rpce-headless-agent-life-home-")
    env["CFFIXED_USER_HOME"] = env["HOME"]
    if extra_env:
        env.update(extra_env)
    return subprocess.Popen(
        [binary, "serve", "--root", str(root)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


class Harness:
    def __init__(self, binary, root, fake_agent, agent_config, extra_env=None):
        self.process = start_server(binary, root, fake_agent, agent_config, extra_env=extra_env)
        self.ids = itertools.count(1)
        self.initialize()

    def rpc(self, method, params=None):
        i = next(self.ids)
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params or {}}) + "\n")
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                err = self.process.stderr.read()
                raise AssertionError(f"server closed stdout while waiting for {method}; stderr={err}")
            msg = json.loads(line)
            if msg.get("id") == i:
                assert "error" not in msg, f"{method} -> {msg['error']}"
                return msg["result"]

    def notify(self, method, params=None):
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}}) + "\n")
        self.process.stdin.flush()

    def call(self, name, arguments=None):
        result = self.rpc("tools/call", {"name": name, "arguments": arguments or {}})
        text = "".join(c.get("text", "") for c in result.get("content", []))
        return result, text

    def payload(self, result, text):
        if result.get("structuredContent") is not None:
            return result["structuredContent"]
        return json.loads(text)

    def initialize(self):
        self.rpc(
            "initialize",
            {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "agent-lifecycle-harness", "version": "0"}},
        )
        self.notify("notifications/initialized")
        tools = {t["name"] for t in self.rpc("tools/list")["tools"]}
        expected = {"agent_run", "agent_manage"}
        assert expected <= tools, f"missing: {expected - tools}; tools={sorted(tools)}"
        assert "agent_explore" not in tools, tools

    def close(self):
        try:
            if self.process.stdin:
                self.process.stdin.close()
        except Exception:
            pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=10)


def tool_payload(harness, name, arguments=None):
    result, text = harness.call(name, arguments)
    assert not result.get("isError"), text
    return harness.payload(result, text)


def session_id(snapshot):
    sid = snapshot.get("session_id") or snapshot.get("session", {}).get("id")
    assert sid, snapshot
    return sid


def wait_for(predicate, description, timeout=10, interval=0.1):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timed out waiting for {description}; last={last!r}")


def pid_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def pid_process_group(pid):
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError:
        return None
    except PermissionError:
        return "unknown"
    fields = stat.split()
    if len(fields) < 5:
        return "unknown"
    try:
        return int(fields[4])
    except ValueError:
        return "unknown"


def pid_state(pid):
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError:
        return None
    except PermissionError:
        return "unknown"
    fields = stat.split()
    if len(fields) < 3:
        return "unknown"
    return fields[2]


def assert_pid_left_process_group(pid, label, process_group_id):
    def left_group():
        if not pid_exists(pid):
            return True
        if pid_state(pid) == "Z":
            return True
        pgid = pid_process_group(pid)
        return pgid is not None and pgid != process_group_id

    wait_for(left_group, f"{label} pid {pid} to leave process group {process_group_id}", timeout=10, interval=0.5)


def log_text(harness, sid):
    payload = tool_payload(harness, "agent_manage", {"op": "get_log", "session_id": sid})
    return json.dumps(payload)


def wait_for_log_pattern(harness, sid, pattern, description):
    regex = re.compile(pattern)

    def find_match():
        match = regex.search(log_text(harness, sid))
        return match

    return wait_for(find_match, description, timeout=10, interval=0.2)


def start_agent(harness, model_id, message, detach=True, timeout=None):
    args = {"op": "start", "model_id": model_id, "message": message, "detach": detach}
    if timeout is not None:
        args["timeout"] = timeout
    return tool_payload(harness, "agent_run", args)


def wait_session(harness, sid, timeout):
    return tool_payload(harness, "agent_run", {"op": "wait", "session_id": sid, "timeout": timeout})


def cancel_and_wait(harness, sid, timeout=15):
    cancel = tool_payload(harness, "agent_run", {"op": "cancel", "session_id": sid})
    assert cancel.get("status") in {"cancelling", "cancelled"}, cancel
    waited = wait_session(harness, sid, timeout)
    assert waited.get("status") == "cancelled", waited
    return waited


def make_agent_config(sleeping_agent):
    return {
        "fake": {
            "argv": ["python3", "{FAKE_AGENT_SCRIPT}", "{MCP_CONFIG_PATH_RAW}"],
            "promptVia": "env",
        },
        "sleeper": {
            "argv": ["python3", str(sleeping_agent)],
            "promptVia": "env",
        },
        "missing": {
            "argv": ["/nonexistent/rpce-agent-binary"],
            "promptVia": "env",
        },
    }


def run_fast_scenarios(binary, root, fake_agent, agent_config):
    harness = Harness(binary, root, fake_agent, agent_config)
    try:
        print("lifecycle: detach + poll + wait", flush=True)
        message = "detach poll wait lifecycle"
        start = start_agent(harness, "fake", message, detach=True)
        sid = session_id(start)
        assert start.get("status") in {"running", "completed"}, start
        poll = tool_payload(harness, "agent_run", {"op": "poll", "session_id": sid})
        assert poll.get("session_id") == sid, poll
        waited = wait_session(harness, sid, 30)
        assert waited.get("status") == "completed", waited
        assert "RPCE_AGENT_SMOKE_SENTINEL" in json.dumps(waited), waited
        assert message in json.dumps(waited), waited

        print("lifecycle: missing binary", flush=True)
        result, text = harness.call("agent_run", {"op": "start", "model_id": "missing", "message": "missing binary", "detach": True})
        assert result.get("isError"), text
        assert "/nonexistent/rpce-agent-binary" in text or "No such file" in text, text

        print("lifecycle: concurrent isolation", flush=True)
        left_message = "lifecycle concurrent left"
        right_message = "lifecycle concurrent right"
        left = start_agent(harness, "fake", left_message, detach=True)
        right = start_agent(harness, "fake", right_message, detach=True)
        left_id = session_id(left)
        right_id = session_id(right)
        assert left_id != right_id, (left, right)
        left_wait = wait_session(harness, left_id, 30)
        right_wait = wait_session(harness, right_id, 30)
        assert left_wait.get("status") == "completed", left_wait
        assert right_wait.get("status") == "completed", right_wait
        left_log = log_text(harness, left_id)
        right_log = log_text(harness, right_id)
        assert left_message in left_log, left_log
        assert right_message not in left_log, left_log
        assert right_message in right_log, right_log
        assert left_message not in right_log, right_log
    finally:
        harness.close()


def run_sleep_scenarios(binary, root, fake_agent, agent_config):
    harness = Harness(
        binary,
        root,
        fake_agent,
        agent_config,
        extra_env={"FAKE_AGENT_SLEEP": "600", "FAKE_AGENT_SPAWN_CHILD": "1"},
    )
    try:
        print("lifecycle: wait timeout", flush=True)
        timeout_start = start_agent(harness, "sleeper", "timeout sleeper", detach=True)
        timeout_id = session_id(timeout_start)
        timed_out = wait_session(harness, timeout_id, 1)
        assert timed_out.get("status") == "running", timed_out
        assert timed_out.get("_meta", {}).get("wait_result") == "timed_out", timed_out

        print("lifecycle: cancel kills process tree", flush=True)
        agent_pid = int(wait_for_log_pattern(harness, timeout_id, r"LIFECYCLE_AGENT_PID:(\d+)", "agent pid").group(1))
        child_pid = int(wait_for_log_pattern(harness, timeout_id, r"LIFECYCLE_CHILD_PID:(\d+)", "child pid").group(1))
        cancel_and_wait(harness, timeout_id)
        assert_pid_left_process_group(agent_pid, "agent", agent_pid)
        assert_pid_left_process_group(child_pid, "child", agent_pid)

        print("lifecycle: stop_session", flush=True)
        stop_start = start_agent(harness, "sleeper", "stop sleeper", detach=True)
        stop_id = session_id(stop_start)
        stop_agent_pid = int(wait_for_log_pattern(harness, stop_id, r"LIFECYCLE_AGENT_PID:(\d+)", "stop_session agent pid").group(1))
        stop = tool_payload(harness, "agent_manage", {"op": "stop_session", "session_id": stop_id})
        assert stop.get("stop_requested") is True, stop
        stopped = wait_session(harness, stop_id, 15)
        assert stopped.get("status") == "cancelled", stopped
        assert_pid_left_process_group(stop_agent_pid, "stop_session agent", stop_agent_pid)

        print("lifecycle: cleanup guard", flush=True)
        cleanup_start = start_agent(harness, "sleeper", "cleanup guard sleeper", detach=True)
        cleanup_id = session_id(cleanup_start)
        cleanup = tool_payload(harness, "agent_manage", {"op": "cleanup_sessions", "session_ids": [cleanup_id]})
        assert cleanup.get("skipped_count") == 1, cleanup
        assert cleanup.get("deleted_count") == 0, cleanup
        skipped = cleanup.get("skipped_sessions", [])
        assert any(item.get("session_id") == cleanup_id and item.get("reason") == "skipped_active" for item in skipped), cleanup
        cancel_and_wait(harness, cleanup_id)
        deleted = tool_payload(harness, "agent_manage", {"op": "cleanup_sessions", "session_ids": [cleanup_id]})
        assert deleted.get("deleted_count") == 1, deleted
        assert deleted.get("skipped_count") == 0, deleted
    finally:
        harness.close()


def main():
    parser = argparse.ArgumentParser(description="Smoke-test headless agent lifecycle behavior over MCP stdio.")
    parser.add_argument("binary")
    parser.add_argument("root", nargs="?", help="Workspace root. Defaults to a temporary workspace.")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="rpce-headless-agent-life-") as tmp:
        tmp_path = Path(tmp)
        root = Path(args.root) if args.root else tmp_path / "workspace"
        root.mkdir(parents=True, exist_ok=True)
        (root / "smoke.txt").write_text("hello headless lifecycle smoke\n")

        fake_agent = tmp_path / "fake_agent.py"
        sleeping_agent = tmp_path / "sleeping_agent.py"
        agent_config = tmp_path / "agents.json"
        write_file(fake_agent, FAKE_AGENT, 0o700)
        write_file(sleeping_agent, SLEEPING_AGENT, 0o700)
        write_file(agent_config, json.dumps(make_agent_config(sleeping_agent)))

        run_fast_scenarios(args.binary, root, fake_agent, agent_config)
        run_sleep_scenarios(args.binary, root, fake_agent, agent_config)

    print("AGENT LIFECYCLE SMOKE OK")


if __name__ == "__main__":
    main()
