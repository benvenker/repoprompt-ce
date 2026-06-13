#!/usr/bin/env python3
import itertools, json, os, subprocess, sys, tempfile

binary, root = sys.argv[1], sys.argv[2]

FAKE_AGENT = r'''
#!/usr/bin/env python3
import itertools, json, os, subprocess, sys

config_path = sys.argv[1]
if os.environ.get("FAKE_AGENT_EXIT"):
    sys.exit(int(os.environ["FAKE_AGENT_EXIT"]))
if os.environ.get("FAKE_AGENT_EMPTY"):
    sys.exit(0)
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
