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
listed_tools = rpc("tools/list")["tools"]
tools = {t["name"] for t in listed_tools}
expected = {"headless_capabilities","headless_status","read_file","get_file_tree","file_search","get_code_structure",
            "manage_selection","workspace_context","prompt","oracle_send","context_builder","agent_manage","agent_run"}
assert expected <= tools, f"missing: {expected - tools}"
tool_names = [t["name"] for t in listed_tools]
assert tool_names[:5] == ["headless_status", "headless_capabilities", "context_builder", "agent_manage", "agent_run"], tool_names
descriptions = {t["name"]: t.get("description", "") for t in listed_tools}
assert "Preferred repo-onboarding" in descriptions["context_builder"], descriptions["context_builder"]
assert "original result shape" in descriptions["context_builder"], descriptions["context_builder"]
assert "running lifecycle snapshot" in descriptions["context_builder"], descriptions["context_builder"]
assert "server-managed subagent lifecycle" in descriptions["agent_run"], descriptions["agent_run"]
assert "instead of client-local" in descriptions["agent_manage"], descriptions["agent_manage"]
print("INIT OK", sorted(tools))
if phase != "init" and "all" in (phase,):
    def call_result(name, args):
        r = rpc("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text","") for c in r.get("content",[]))
        assert not r.get("isError"), f"{name} errored: {text[:400]}"
        return r, text
    def call(name, args):
        return call_result(name, args)[1]
    capabilities_result, capabilities_text = call_result("headless_capabilities", {})
    capabilities = capabilities_result.get("structuredContent") or json.loads(capabilities_text)
    assert root in capabilities["loaded_roots"], capabilities
    assert any(item["path"] == root for item in capabilities["loaded_root_metadata"]), capabilities
    assert "headless_status" in capabilities["recommended_workflow"][0], capabilities
    assert "headless_capabilities" in capabilities["recommended_workflow"][1], capabilities
    assert any("context_builder" in step for step in capabilities["recommended_workflow"]), capabilities
    assert capabilities["native_workflows"]["source"].startswith("RepoPrompt CE native"), capabilities
    assert {"explore", "engineer", "pair", "design"} <= {r["name"] for r in capabilities["native_workflows"]["roles"]}, capabilities
    assert {"investigate", "optimize", "deep_plan"} <= {w["name"] for w in capabilities["native_workflows"]["workflows"]}, capabilities
    assert capabilities["native_workflows"]["custom_workflows"]["current_headless_support"] == "metadata_only", capabilities
    assert "running lifecycle snapshot" in capabilities["context_builder"]["timeout_guidance"], capabilities
    assert "RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS" in capabilities["context_builder"]["timeout_guidance"], capabilities
    status_result, status_text = call_result("headless_status", {})
    status = status_result.get("structuredContent") or json.loads(status_text)
    assert root in status["loaded_roots"], status
    assert any(item["path"] == root for item in status["loaded_root_metadata"]), status
    assert status["suggested_first_tool_calls"][0] == "headless_status", status
    assert "context_builder" in status["suggested_first_tool_calls"][1], status
    assert "agent_manage" in status["suggested_first_tool_calls"][2], status
    assert "agent_run" in status["suggested_first_tool_calls"][3], status
    assert status["available_agent_tools"]["context_builder"], status
    assert "native_workflows" in status and status["native_workflows"]["workflows"], status
    assert status["native_workflows"]["custom_workflows"]["current_headless_support"] == "metadata_only", status
    assert "Package.swift" in call("get_file_tree", {"mode":"full", "path": root, "max_depth": 1})
    assert "RepoPromptContextCore" in call("file_search", {"pattern":"RepoPromptContextCore","max_results":5})
    assert "swift-tools-version" in call("read_file", {"path":"Package.swift","start_line":1,"limit":3})
    structure_result, structure_text = call_result("get_code_structure", {"paths":["Sources/RepoPromptShared/MCP/MCPControlMessages.swift"]})
    structure_payload = structure_result.get("structuredContent", {})
    if structure_payload.get("structure_count", 0) >= 1:
        assert "struct" in structure_text.lower()
    else:
        assert structure_payload["files"][0]["status"] == "codemap_unavailable", structure_payload
        assert structure_payload["files"][0]["fallback_tools"] == ["file_search", "read_file"], structure_payload
    fallback_result, fallback_text = call_result("get_code_structure", {"paths":["AGENTS.md"]})
    fallback = fallback_result.get("structuredContent") or json.loads(fallback_text)
    assert fallback["files"][0]["path"] == "AGENTS.md", fallback
    assert fallback["files"][0]["status"] == "codemap_unavailable", fallback
    assert fallback["files"][0]["fallback_tools"] == ["file_search", "read_file"], fallback
    call("manage_selection", {"op":"add","paths":["Package.swift"]})
    assert "Package.swift" in call("manage_selection", {"op":"get","view":"files"})
    call("prompt", {"op":"set","text":"hello prompt"})
    assert "hello prompt" in call("prompt", {"op":"get"})
    wc_result, wc = call_result("workspace_context", {})
    wc_structured = wc_result.get("structuredContent") or {}
    assert root in wc_structured.get("loaded_roots", []), wc_structured
    assert any(item["path"] == root for item in wc_structured.get("loaded_root_metadata", [])), wc_structured
    assert "Package.swift" in wc
    print("ALL OK")
p.stdin.close(); p.wait(timeout=10)
