#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile, textwrap, itertools

binary, root = sys.argv[1], sys.argv[2]

FAKE_AGENT = r'''
#!/usr/bin/env python3
import json, subprocess, sys, itertools, os

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

rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"fake-agent","version":"0"}})
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
_, search_text = call("file_search", {"pattern":"swift-tools-version", "max_results": 5})
assert "Package.swift" in search_text or "swift-tools-version" in search_text, search_text
sel, sel_text = call("manage_selection", {"op":"add", "paths":["Package.swift"]})
assert not sel.get("isError"), sel_text
prompt, prompt_text = call("prompt", {"op":"set", "text":"<taskname=\"Fake\"/> fake handoff"})
assert not prompt.get("isError"), prompt_text
ctx, ctx_text = call("workspace_context", {"include":["selection","prompt","tokens"]})
assert "Package.swift" in ctx_text, ctx_text[:500]
p.stdin.close()
p.wait(timeout=10)
sys.exit(0)
'''

def write_fake_agent():
    fd, path = tempfile.mkstemp(prefix="rpce-fake-agent-", suffix=".py")
    with os.fdopen(fd, "w") as f:
        f.write(FAKE_AGENT)
    os.chmod(path, 0o700)
    return path

def run_context(fake_agent, extra_env=None, extra_args=None, remove_oracle_keys=False):
    env = dict(os.environ)
    env["FAKE_AGENT_SCRIPT"] = fake_agent
    env["HOME"] = tempfile.mkdtemp(prefix="rpce-headless-home-")
    env["CFFIXED_USER_HOME"] = env["HOME"]
    if remove_oracle_keys:
        env.pop("RPCE_ORACLE_API_KEY", None)
        env.pop("OPENROUTER_API_KEY", None)
    if extra_env:
        env.update(extra_env)
    args = [binary, "context-build", "--root", root, "--agent", "fake", "--instructions", "test", "--timeout", "30"]
    if extra_args:
        args.extend(extra_args)
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=60,
    )

fake = write_fake_agent()
try:
    ok = run_context(fake)
    assert ok.returncode == 0, f"expected success, got {ok.returncode}\nSTDOUT:\n{ok.stdout}\nSTDERR:\n{ok.stderr}"
    assert "== context-build report ==" in ok.stdout, ok.stdout
    assert "agent exit: 0" in ok.stdout, ok.stdout
    assert "Package.swift" in ok.stdout, ok.stdout
    assert "fake handoff" in ok.stdout, ok.stdout
    report_header = ok.stdout.split("selection", 1)[0]
    assert "oracle_send" not in report_header, ok.stdout
    assert "context_builder" not in report_header, ok.stdout

    fail = run_context(fake, {"FAKE_AGENT_EXIT": "3"})
    assert fail.returncode != 0, f"expected nonzero propagation\nSTDOUT:\n{fail.stdout}\nSTDERR:\n{fail.stderr}"
    assert "agent exit: 3" in fail.stdout, fail.stdout

    fail_question = run_context(
        fake,
        {"FAKE_AGENT_EXIT": "3"},
        ["--response-type", "question"],
        remove_oracle_keys=True,
    )
    assert fail_question.returncode == 3, f"expected exit 3 propagation\nSTDOUT:\n{fail_question.stdout}\nSTDERR:\n{fail_question.stderr}"
    assert "agent exit: 3" in fail_question.stdout, fail_question.stdout
    assert "answer:" not in fail_question.stdout, fail_question.stdout

    empty_question = run_context(
        fake,
        {"FAKE_AGENT_EMPTY": "1"},
        ["--response-type", "question"],
        remove_oracle_keys=True,
    )
    assert empty_question.returncode == 2, f"expected empty-selection exit 2\nSTDOUT:\n{empty_question.stdout}\nSTDERR:\n{empty_question.stderr}"
    assert "agent exit: 0" in empty_question.stdout, empty_question.stdout
    assert "selection (0 files" in empty_question.stdout, empty_question.stdout
    assert "answer:" not in empty_question.stdout, empty_question.stdout
    print("CONTEXT_BUILD OK")
finally:
    try:
        os.remove(fake)
    except OSError:
        pass
