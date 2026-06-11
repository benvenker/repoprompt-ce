#!/usr/bin/env python3
# Starts a local OpenAI-compatible mock (SSE), points rpce-headless at it,
# calls oracle_send over MCP stdio, asserts the streamed reply round-trips.
import json, os, subprocess, sys, threading, itertools, tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer

binary, root = sys.argv[1], sys.argv[2]
live = "--live" in sys.argv

class Mock(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert self.headers["Authorization"].startswith("Bearer "), "missing bearer"
        assert body["model"] == "mock-model", body
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for chunk in ["MOCK_", "REPLY_", "OK"]:
            evt = {"choices": [{"delta": {"content": chunk}}]}
            self.wfile.write(f"data: {json.dumps(evt)}\n\n".encode())
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()
    def log_message(self, *a): pass

def start_server(env):
    return subprocess.Popen([binary, "serve", "--root", root], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=sys.stderr, text=True, env=env)

ids = itertools.count(1)
def rpc(p, method, params=None):
    i = next(ids)
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            sys.exit("server closed stdout")
        msg = json.loads(line)
        if msg.get("id") == i:
            assert "error" not in msg, msg["error"]
            return msg["result"]

def notify(p, method, params=None):
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()

def initialize(p):
    rpc(p, "initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                          "clientInfo": {"name": "t", "version": "0"}})
    notify(p, "notifications/initialized")

env = dict(os.environ)
test_home = tempfile.mkdtemp(prefix="rpce-headless-home-")
env["HOME"] = test_home
env["CFFIXED_USER_HOME"] = test_home
if not live:
    srv = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    env["RPCE_ORACLE_BASE_URL"] = f"http://127.0.0.1:{srv.server_port}/v1"
    env["RPCE_ORACLE_API_KEY"] = "mock-key"
    env["RPCE_ORACLE_MODEL"] = "mock-model"

p = start_server(env)
initialize(p)
r = rpc(p, "tools/call", {"name": "oracle_send", "arguments": {"message": "ping", "include_context": False}})
text = "".join(c.get("text", "") for c in r.get("content", []))
assert not r.get("isError"), text[:400]
if live:
    assert len(text.split("|", 1)[-1].strip()) > 0
    print("ORACLE LIVE OK")
else:
    assert "MOCK_REPLY_OK" in text, text[:400]
    # continuation: same chat_id second turn must not error
    cid = text.split("chat_id:", 1)[1].split("|")[0].strip()
    r2 = rpc(p, "tools/call", {"name": "oracle_send", "arguments": {"message": "again", "chat_id": cid}})
    assert not r2.get("isError")
    text2 = "".join(c.get("text", "") for c in r2.get("content", []))
    assert "MOCK_REPLY_OK" in text2, text2[:400]
    session_path = os.path.join(test_home, "Library", "Application Support", "rpce-headless", "chats", f"{cid}.json")
    with open(session_path) as f:
        session = json.load(f)
    assert session["id"] == cid, session
    assert [m["role"] for m in session["messages"]] == ["user", "assistant", "user", "assistant"], session
p.stdin.close()
p.wait(timeout=10)

if not live:
    missing_env = dict(os.environ)
    missing_env["HOME"] = test_home
    missing_env["CFFIXED_USER_HOME"] = test_home
    missing_env.pop("RPCE_ORACLE_API_KEY", None)
    missing_env.pop("OPENROUTER_API_KEY", None)
    missing_env["RPCE_ORACLE_BASE_URL"] = env["RPCE_ORACLE_BASE_URL"]
    missing_env["RPCE_ORACLE_MODEL"] = "mock-model"
    p = start_server(missing_env)
    initialize(p)
    missing = rpc(p, "tools/call", {"name": "oracle_send", "arguments": {"message": "ping", "include_context": False}})
    missing_text = "".join(c.get("text", "") for c in missing.get("content", []))
    assert missing.get("isError"), missing_text
    assert "RPCE_ORACLE_API_KEY" in missing_text or "OPENROUTER_API_KEY" in missing_text, missing_text
    p.stdin.close()
    p.wait(timeout=10)
    print("ORACLE OK")
