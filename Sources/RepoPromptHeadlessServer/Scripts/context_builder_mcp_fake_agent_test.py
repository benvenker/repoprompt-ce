#!/usr/bin/env python3
import itertools, json, os, subprocess, sys, tempfile, time

binary, root = sys.argv[1], sys.argv[2]

FAKE_AGENT = r'''
#!/usr/bin/env python3
import itertools, json, os, signal, subprocess, sys, time

config_path = sys.argv[1]
pid_file = os.environ.get("FAKE_AGENT_PID_FILE")
if pid_file:
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))
if os.environ.get("FAKE_AGENT_IGNORE_SIGTERM"):
    signal.signal(signal.SIGTERM, lambda signum, frame: None)
if os.environ.get("FAKE_AGENT_EXIT"):
    sys.exit(int(os.environ["FAKE_AGENT_EXIT"]))
if os.environ.get("FAKE_AGENT_EMPTY"):
    sys.exit(0)
diagnostic_stdout = os.environ.get("FAKE_AGENT_DIAGNOSTIC_STDOUT")
if diagnostic_stdout is not None:
    print(diagnostic_stdout, flush=True)
diagnostic_stderr = os.environ.get("FAKE_AGENT_DIAGNOSTIC_STDERR")
if diagnostic_stderr is not None:
    print(diagnostic_stderr, file=sys.stderr, flush=True)
sleep_before_mcp = float(os.environ.get("FAKE_AGENT_SLEEP_BEFORE_MCP", "0"))
if sleep_before_mcp:
    if not os.environ.get("FAKE_AGENT_QUIET_SLEEP"):
        print(f"CONTEXT_BUILDER_FAKE_SLEEPING:{sleep_before_mcp}", flush=True)
    time.sleep(sleep_before_mcp)
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

def call(name, args=None):
    result = rpc("tools/call", {"name": name, "arguments": args or {}})
    text = "".join(c.get("text", "") for c in result.get("content", []))
    return result, text

rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"fake-context-builder-agent","version":"0"}})
notify("notifications/initialized")
tools = {t["name"] for t in rpc("tools/list")["tools"]}
expected = {"read_file","get_file_tree","file_search","get_code_structure","manage_selection","workspace_context","prompt"}
assert expected <= tools, tools
assert "oracle_send" not in tools, tools
assert "context_builder" not in tools, tools
oracle, oracle_text = call("oracle_send", {"message":"must be blocked"})
assert oracle.get("isError"), oracle_text
assert "discovery-restricted" in oracle_text, oracle_text
context_builder, context_builder_text = call("context_builder", {"instructions":"must be blocked"})
assert context_builder.get("isError"), context_builder_text
assert "discovery-restricted" in context_builder_text, context_builder_text
sel, sel_text = call("manage_selection", {"op":"add", "paths":["Package.swift"]})
assert not sel.get("isError"), sel_text
prompt, prompt_text = call("prompt", {"op":"set", "text":"<taskname=\"Fake MCP Context Builder\"/> fake handoff from mcp context_builder"})
assert not prompt.get("isError"), prompt_text
ctx, ctx_text = call("workspace_context", {"include":["selection","prompt","tokens"]})
assert "Package.swift" in ctx_text, ctx_text[:500]
p.stdin.close()
p.wait(timeout=10)
sys.exit(0)
'''

def write_fake_agent():
    fd, path = tempfile.mkstemp(prefix="rpce-context-builder-fake-agent-", suffix=".py")
    with os.fdopen(fd, "w") as f:
        f.write(FAKE_AGENT)
    os.chmod(path, 0o700)
    return path

def start_server(fake_agent, extra_env=None, remove_oracle_keys=False):
    env = dict(os.environ)
    env["FAKE_AGENT_SCRIPT"] = fake_agent
    env["RPCE_CONTEXT_BUILDER_AGENT"] = "fake"
    env["HOME"] = tempfile.mkdtemp(prefix="rpce-headless-home-")
    env["CFFIXED_USER_HOME"] = env["HOME"]
    if remove_oracle_keys:
        env.pop("RPCE_ORACLE_API_KEY", None)
        env.pop("OPENROUTER_API_KEY", None)
    if extra_env:
        env.update(extra_env)
    return subprocess.Popen(
        [binary, "serve", "--root", root],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False

def wait_for_file(path, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
        time.sleep(0.05)
    raise AssertionError(f"timed out waiting for {path}")

def main():
    fake = write_fake_agent()
    p = None
    try:
        p = start_server(fake)
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

        def call(name, args=None):
            result = rpc("tools/call", {"name": name, "arguments": args or {}})
            text = "".join(c.get("text", "") for c in result.get("content", []))
            return result, text

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        tools = {t["name"] for t in rpc("tools/list")["tools"]}
        expected = {"read_file","get_file_tree","file_search","get_code_structure","manage_selection","workspace_context","prompt","oracle_send","context_builder"}
        assert expected <= tools, f"missing: {expected - tools}; tools={sorted(tools)}"

        result, text = call("context_builder", {
            "instructions": "Map enough context to prove the MCP context_builder fake-agent harness works.",
            "response_type": "clarify",
            "export_response": False,
        })
        assert not result.get("isError"), text
        payload = result.get("structuredContent")
        if payload is None:
            payload = json.loads(text)
        assert payload.get("status") == "completed", payload
        assert payload.get("context_id"), payload
        assert "fake handoff from mcp context_builder" in payload.get("prompt", ""), payload
        assert "Package.swift" in json.dumps(payload.get("selection", "")), payload
        assert payload.get("file_count", 0) >= 1, payload
        assert payload.get("total_tokens", 0) > 0, payload
        assert payload.get("response_type") in (None, "clarify"), payload

        p.stdin.close()
        p.wait(timeout=10)
        p = start_server(fake, {"FAKE_AGENT_SLEEP_BEFORE_MCP": "2.5"}, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        started_at = __import__("time").monotonic()
        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Async fixture should eventually select Package.swift.",
            "response_type": "clarify",
            "export_response": False,
        })
        elapsed = __import__("time").monotonic() - started_at
        assert elapsed < 1.5, f"start should return before fake agent sleep completes; elapsed={elapsed}"
        assert not result.get("isError"), text
        start_payload = result.get("structuredContent") or json.loads(text)
        context_id = start_payload.get("context_id")
        assert context_id, start_payload
        assert start_payload.get("run_status") == "running", start_payload
        assert "selection" not in start_payload, start_payload

        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Second start should be rejected while single-flight run is active.",
            "response_type": "clarify",
        })
        assert result.get("isError"), text
        assert "already running" in text and context_id in text, text

        result, text = call("context_builder", {"op": "poll", "context_id": context_id})
        assert not result.get("isError"), text
        poll_payload = result.get("structuredContent") or json.loads(text)
        assert poll_payload.get("run_status") == "running", poll_payload
        assert poll_payload.get("context_id") == context_id, poll_payload

        result, text = call("context_builder", {"op": "wait", "context_id": context_id, "timeout": 1})
        assert not result.get("isError"), text
        wait_payload = result.get("structuredContent") or json.loads(text)
        assert wait_payload.get("run_status") == "running", wait_payload
        assert wait_payload.get("_meta", {}).get("wait_result") == "timed_out", wait_payload

        result, text = call("context_builder", {"op": "wait", "context_id": context_id, "timeout": 20})
        assert not result.get("isError"), text
        done_payload = result.get("structuredContent") or json.loads(text)
        assert done_payload.get("run_status") == "completed", done_payload
        assert done_payload.get("result_status") == "completed", done_payload

        result, text = call("context_builder", {"op": "get_result", "context_id": context_id})
        assert not result.get("isError"), text
        payload = result.get("structuredContent") or json.loads(text)
        assert payload.get("status") == "completed", payload
        assert "fake handoff from mcp context_builder" in payload.get("prompt", ""), payload
        assert "Package.swift" in json.dumps(payload.get("selection", "")), payload

        result, text = call("context_builder", {"op": "cleanup", "context_id": context_id})
        assert not result.get("isError"), text
        cleanup_payload = result.get("structuredContent") or json.loads(text)
        assert cleanup_payload.get("deleted_count") == 1, cleanup_payload
        result, text = call("context_builder", {"op": "poll", "context_id": context_id})
        assert not result.get("isError"), text
        expired_payload = result.get("structuredContent") or json.loads(text)
        assert expired_payload.get("run_status") == "expired", expired_payload

        p.stdin.close()
        p.wait(timeout=10)
        p = start_server(fake, {"FAKE_AGENT_SLEEP_BEFORE_MCP": "600"}, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Async fixture should be cancellable before discovery completes.",
            "response_type": "clarify",
            "export_response": False,
        })
        assert not result.get("isError"), text
        cancel_id = (result.get("structuredContent") or json.loads(text)).get("context_id")
        assert cancel_id, text
        result, text = call("context_builder", {"op": "cancel", "context_id": cancel_id})
        assert not result.get("isError"), text
        cancel_payload = result.get("structuredContent") or json.loads(text)
        assert cancel_payload.get("run_status") == "cancelled", cancel_payload
        result, text = call("context_builder", {"op": "get_result", "context_id": cancel_id})
        assert result.get("isError"), text
        assert "did not complete successfully" in text, text
        assert cancel_id in text and "run_status is cancelled" in text, text
        result, text = call("context_builder", {"op": "cleanup", "context_id": cancel_id})
        assert not result.get("isError"), text
        cleanup_payload = result.get("structuredContent") or json.loads(text)
        assert cleanup_payload.get("deleted_count") == 1, cleanup_payload

        p.stdin.close()
        p.wait(timeout=10)
        shutdown_pid_file = tempfile.mktemp(prefix="rpce-context-builder-shutdown-pid-")
        p = start_server(fake, {
            "FAKE_AGENT_SLEEP_BEFORE_MCP": "600",
            "FAKE_AGENT_IGNORE_SIGTERM": "1",
            "FAKE_AGENT_PID_FILE": shutdown_pid_file,
        }, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Async fixture should be killed during server shutdown.",
            "response_type": "clarify",
            "export_response": False,
        })
        assert not result.get("isError"), text
        shutdown_id = (result.get("structuredContent") or json.loads(text)).get("context_id")
        assert shutdown_id, text
        fake_pid = int(wait_for_file(shutdown_pid_file))
        assert pid_alive(fake_pid), fake_pid
        p.stdin.close()
        p.wait(timeout=12)
        assert not pid_alive(fake_pid), f"fake agent survived server shutdown: pid={fake_pid}"
        try:
            os.remove(shutdown_pid_file)
        except OSError:
            pass

        p = start_server(fake, {
            "FAKE_AGENT_SLEEP_BEFORE_MCP": "600",
            "FAKE_AGENT_DIAGNOSTIC_STDOUT": "CTX_TIMEOUT_STDOUT_SENTINEL|" + ("x" * 200),
            "FAKE_AGENT_DIAGNOSTIC_STDERR": "CTX_TIMEOUT_STDERR_SENTINEL|" + ("y" * 200),
            "RPCE_CONTEXT_BUILDER_OUTPUT_CAPTURE_LIMIT_BYTES": "80",
        }, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Async fixture should time out instead of later reporting completion.",
            "response_type": "clarify",
            "timeout_seconds": 1,
            "export_response": False,
        })
        assert not result.get("isError"), text
        timeout_id = (result.get("structuredContent") or json.loads(text)).get("context_id")
        assert timeout_id, text
        result, text = call("context_builder", {"op": "wait", "context_id": timeout_id, "timeout": 10})
        assert not result.get("isError"), text
        timeout_payload = result.get("structuredContent") or json.loads(text)
        assert timeout_payload.get("run_status") == "failed", timeout_payload
        assert "timed out" in timeout_payload.get("error", ""), timeout_payload
        diagnostics = timeout_payload.get("diagnostics") or {}
        assert diagnostics.get("stdout", "").startswith("CTX_TIMEOUT_STDOUT_SENTINEL|"), diagnostics
        assert diagnostics.get("stderr", "").startswith("CTX_TIMEOUT_STDERR_SENTINEL|"), diagnostics
        assert diagnostics.get("stdout_truncated") is True, diagnostics
        assert diagnostics.get("stderr_truncated") is True, diagnostics
        assert diagnostics.get("output_capture_limit_bytes") == 80, diagnostics
        assert diagnostics.get("output_capture_enabled") is True, diagnostics
        assert diagnostics.get("output_empty") is False, diagnostics
        assert diagnostics.get("timeout_seconds") == 1, diagnostics
        assert isinstance(diagnostics.get("process_id"), int), diagnostics
        assert diagnostics.get("termination_status") == "sigkill_requested_after_timeout", diagnostics
        result, text = call("context_builder", {"op": "get_result", "context_id": timeout_id})
        assert result.get("isError"), text
        assert "did not complete successfully" in text, text
        assert timeout_id in text and "run_status is failed" in text and "timed out" in text, text
        assert "CTX_TIMEOUT_STDOUT_SENTINEL|" in text and "CTX_TIMEOUT_STDERR_SENTINEL|" in text, text
        assert "stdout_truncated=true" in text and "stderr_truncated=true" in text, text
        assert "output_empty=false" in text and "termination_status: sigkill_requested_after_timeout" in text, text
        result, text = call("context_builder", {"op": "cleanup", "context_id": timeout_id})
        assert not result.get("isError"), text
        cleanup_payload = result.get("structuredContent") or json.loads(text)
        assert cleanup_payload.get("deleted_count") == 1, cleanup_payload

        p.stdin.close()
        p.wait(timeout=10)
        p = start_server(fake, {
            "FAKE_AGENT_SLEEP_BEFORE_MCP": "600",
            "FAKE_AGENT_QUIET_SLEEP": "1",
            "RPCE_CONTEXT_BUILDER_OUTPUT_CAPTURE_LIMIT_BYTES": "80",
        }, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "op": "start",
            "instructions": "Async fixture should time out quietly but still report diagnostics.",
            "response_type": "clarify",
            "timeout_seconds": 1,
            "export_response": False,
        })
        assert not result.get("isError"), text
        quiet_timeout_id = (result.get("structuredContent") or json.loads(text)).get("context_id")
        assert quiet_timeout_id, text
        result, text = call("context_builder", {"op": "wait", "context_id": quiet_timeout_id, "timeout": 10})
        assert not result.get("isError"), text
        quiet_timeout_payload = result.get("structuredContent") or json.loads(text)
        assert quiet_timeout_payload.get("run_status") == "failed", quiet_timeout_payload
        assert "timed out" in quiet_timeout_payload.get("error", ""), quiet_timeout_payload
        diagnostics = quiet_timeout_payload.get("diagnostics") or {}
        assert diagnostics.get("stdout") == "", diagnostics
        assert diagnostics.get("stderr") == "", diagnostics
        assert diagnostics.get("stdout_truncated") is False, diagnostics
        assert diagnostics.get("stderr_truncated") is False, diagnostics
        assert diagnostics.get("output_capture_limit_bytes") == 80, diagnostics
        assert diagnostics.get("output_capture_enabled") is True, diagnostics
        assert diagnostics.get("output_empty") is True, diagnostics
        assert diagnostics.get("timeout_seconds") == 1, diagnostics
        assert isinstance(diagnostics.get("process_id"), int), diagnostics
        assert diagnostics.get("termination_status") == "sigkill_requested_after_timeout", diagnostics
        result, text = call("context_builder", {"op": "get_result", "context_id": quiet_timeout_id})
        assert result.get("isError"), text
        assert "did not complete successfully" in text, text
        assert quiet_timeout_id in text and "run_status is failed" in text and "timed out" in text, text
        assert "output_empty=true" in text and "timeout_seconds: 1" in text, text
        assert "termination_status: sigkill_requested_after_timeout" in text, text
        result, text = call("context_builder", {"op": "cleanup", "context_id": quiet_timeout_id})
        assert not result.get("isError"), text
        cleanup_payload = result.get("structuredContent") or json.loads(text)
        assert cleanup_payload.get("deleted_count") == 1, cleanup_payload

        p.stdin.close()
        p.wait(timeout=10)
        p = start_server(fake, {"FAKE_AGENT_EXIT": "3"}, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "instructions": "Answer only if discovery succeeds.",
            "response_type": "question",
            "export_response": False,
        })
        assert not result.get("isError"), text
        payload = result.get("structuredContent")
        if payload is None:
            payload = json.loads(text)
        assert payload.get("status") == "agent_failed", payload
        assert payload.get("agent_exit") == 3, payload
        assert payload.get("plan") is None, payload
        assert payload.get("review") is None, payload
        assert payload.get("follow_up_hint") is None, payload

        p.stdin.close()
        p.wait(timeout=10)
        p = start_server(fake, {"FAKE_AGENT_EMPTY": "1"}, remove_oracle_keys=True)
        ids = itertools.count(1)

        rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"context-builder-mcp-harness","version":"0"}})
        notify("notifications/initialized")
        result, text = call("context_builder", {
            "instructions": "Answer only if discovery selects files.",
            "response_type": "question",
            "export_response": False,
        })
        assert not result.get("isError"), text
        payload = result.get("structuredContent")
        if payload is None:
            payload = json.loads(text)
        assert payload.get("status") == "empty_selection", payload
        assert payload.get("agent_exit") == 0, payload
        assert payload.get("plan") is None, payload
        assert payload.get("review") is None, payload
        assert payload.get("follow_up_hint") is None, payload
        print("CONTEXT_BUILDER_MCP OK")
    finally:
        if p is not None:
            try:
                p.stdin.close()
            except Exception:
                pass
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=10)
        try:
            os.remove(fake)
        except OSError:
            pass

if __name__ == "__main__":
    main()
