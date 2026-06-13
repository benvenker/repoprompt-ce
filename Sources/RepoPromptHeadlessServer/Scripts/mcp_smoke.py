#!/usr/bin/env python3
# Minimal MCP stdio harness: initialize -> tools/list -> per-tool calls.
import argparse, itertools, json, subprocess, sys

parser = argparse.ArgumentParser(description="Smoke-test rpce-headless over MCP stdio.")
parser.add_argument("binary")
parser.add_argument("root")
parser.add_argument("--phase", choices=["init", "all"], default="all")
args = parser.parse_args()
binary, root, phase = args.binary, args.root, args.phase
p = subprocess.Popen([binary, "serve", "--root", root], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
ids = itertools.count(1)
def rpc(method, params=None):
    i = next(ids)
    p.stdin.write(json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params or {}})+"\n"); p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line: sys.exit("server closed stdout")
        msg = json.loads(line)
        if msg.get("id") == i:
            assert "error" not in msg, f"{method} -> {msg['error']}"
            return msg["result"]
def notify(method, params=None):
    p.stdin.write(json.dumps({"jsonrpc":"2.0","method":method,"params":params or {}})+"\n"); p.stdin.flush()
init = rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},
                          "clientInfo":{"name":"harness","version":"0"}})
notify("notifications/initialized")
tools = {t["name"] for t in rpc("tools/list")["tools"]}
expected = {"read_file","get_file_tree","file_search","get_code_structure",
            "manage_selection","workspace_context","prompt","oracle_send","context_builder"}
assert expected <= tools, f"missing: {expected - tools}"
print("INIT OK", sorted(tools))
if phase != "init" and "all" in (phase,):
    def call(name, args):
        r = rpc("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text","") for c in r.get("content",[]))
        assert not r.get("isError"), f"{name} errored: {text[:400]}"
        return text
    assert "Package.swift" in call("get_file_tree", {"mode":"full", "path": root, "max_depth": 1})
    assert "RepoPromptContextCore" in call("file_search", {"pattern":"RepoPromptContextCore","max_results":5})
    assert "swift-tools-version" in call("read_file", {"path":"Package.swift","start_line":1,"limit":3})
    assert "struct" in call("get_code_structure", {"paths":["Sources/RepoPromptShared/MCP/MCPControlMessages.swift"]}).lower()
    call("manage_selection", {"op":"add","paths":["Package.swift"]})
    assert "Package.swift" in call("manage_selection", {"op":"get","view":"files"})
    call("prompt", {"op":"set","text":"hello prompt"})
    assert "hello prompt" in call("prompt", {"op":"get"})
    wc = call("workspace_context", {})
    assert "Package.swift" in wc
    print("ALL OK")
p.stdin.close(); p.wait(timeout=10)
