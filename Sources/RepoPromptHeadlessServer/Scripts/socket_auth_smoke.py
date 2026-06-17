#!/usr/bin/env python3
"""Black-box smoke proof for authenticated full-tool rpce-headless sockets."""
import argparse
import itertools
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

TOKEN = "rpce-socket-auth-token-full-smoke"
WRONG_TOKEN = "rpce-socket-auth-token-wrong-smoke"
SHORT_TOKEN = "short-token-15x"
DISCOVERY_TOOLS = {
    "headless_capabilities",
    "headless_status",
    "read_file",
    "get_file_tree",
    "file_search",
    "get_code_structure",
    "manage_selection",
    "workspace_context",
    "prompt",
}
FULL_ONLY_TOOLS = {"agent_run", "agent_manage", "context_builder", "oracle_send"}
FULL_TOOLS = DISCOVERY_TOOLS | FULL_ONLY_TOOLS
SMOKE_TMP = None


def smoke_env():
    env = dict(os.environ)
    env["HOME"] = tempfile.mkdtemp(prefix="home-", dir=SMOKE_TMP)
    env["CFFIXED_USER_HOME"] = env["HOME"]
    return env


def run_cli_gate(binary, root, tmp_path):
    no_socket = subprocess.run(
        [binary, "serve", "--root", str(root), "--expose-all-tools"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert no_socket.returncode == 64, (no_socket.returncode, no_socket.stdout, no_socket.stderr)
    assert "--expose-all-tools requires --socket" in no_socket.stderr, no_socket.stderr
    assert TOKEN not in no_socket.stderr, no_socket.stderr

    for label, value, fragments in (
        ("missing-token", None, ("RPCE_SOCKET_AUTH_TOKEN", "at least 16")),
        ("blank-token", " \n\t", ("RPCE_SOCKET_AUTH_TOKEN", "at least 16")),
        ("short-token", SHORT_TOKEN, ("RPCE_SOCKET_AUTH_TOKEN", "at least 16")),
    ):
        env = smoke_env()
        if value is None:
            env.pop("RPCE_SOCKET_AUTH_TOKEN", None)
        else:
            env["RPCE_SOCKET_AUTH_TOKEN"] = value
        socket_path = str(tmp_path / f"{label}.sock")
        result = subprocess.run(
            [binary, "serve", "--root", str(root), "--socket", socket_path, "--expose-all-tools"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            env=env,
        )
        assert result.returncode == 64, (label, result.returncode, result.stdout, result.stderr)
        assert result.stdout == "", (label, result.stdout)
        for fragment in fragments:
            assert fragment in result.stderr, (label, fragment, result.stderr)
        assert SHORT_TOKEN not in result.stderr, (label, result.stderr)
        assert TOKEN not in result.stderr, (label, result.stderr)
        assert not Path(socket_path).exists(), (label, socket_path)


def wait_for_socket(path, process, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if Path(path).is_socket():
            return
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"server exited before socket was ready: rc={process.returncode} stderr={stderr}")
        time.sleep(0.05)
    raise AssertionError(f"socket did not appear: {path}")


def start_server(binary, root, socket_path, expose_all_tools):
    env = smoke_env()
    if expose_all_tools:
        env["RPCE_SOCKET_AUTH_TOKEN"] = TOKEN
    else:
        env.pop("RPCE_SOCKET_AUTH_TOKEN", None)

    argv = [binary, "serve", "--root", str(root), "--socket", socket_path]
    if expose_all_tools:
        argv.append("--expose-all-tools")
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    wait_for_socket(socket_path, process)
    return process


def stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def read_socket_line(conn, timeout=5):
    conn.settimeout(timeout)
    data = bytearray()
    while True:
        chunk = conn.recv(1)
        if not chunk:
            return bytes(data)
        if chunk == b"\n":
            return bytes(data)
        data.extend(chunk)


def auth_connect(socket_path, token):
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(socket_path)
    conn.sendall(json.dumps({"rpce_auth": {"token": token}}).encode() + b"\n")
    line = read_socket_line(conn)
    assert line, f"auth server closed before reply for token length {len(token)}"
    reply = json.loads(line.decode())
    return conn, reply


def rpc(conn, ids, method, params=None):
    request_id = next(ids)
    conn.sendall(json.dumps({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params or {},
    }).encode() + b"\n")

    while True:
        line = read_socket_line(conn)
        if not line:
            raise AssertionError(f"socket closed while waiting for {method}")
        msg = json.loads(line.decode())
        assert "rpce_auth" not in msg, f"auth frame appeared in MCP stream: {msg}"
        if msg.get("id") == request_id:
            assert "error" not in msg, f"{method} -> {msg['error']}"
            return msg["result"]


def notify(conn, method, params=None):
    conn.sendall(json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
    }).encode() + b"\n")


def initialize_and_list_tools(conn, client_name):
    ids = itertools.count(1)
    rpc(conn, ids, "initialize", {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": client_name, "version": "0"},
    })
    notify(conn, "notifications/initialized")
    return {tool["name"] for tool in rpc(conn, ids, "tools/list")["tools"]}


def call_tool(conn, ids, name, arguments=None):
    result = rpc(conn, ids, "tools/call", {"name": name, "arguments": arguments or {}})
    text = "".join(content.get("text", "") for content in result.get("content", []))
    return result, text


def assert_server_survives(process, label):
    assert process.poll() is None, f"{label}: server exited unexpectedly rc={process.returncode}"


def run_full_socket_scenarios(socket_path, process):
    conn, reply = auth_connect(socket_path, TOKEN)
    try:
        assert reply == {"rpce_auth": {"status": "accepted"}}, reply
        tools = initialize_and_list_tools(conn, "socket-auth-direct-smoke")
        assert tools == FULL_TOOLS, sorted(tools)
    finally:
        conn.close()
    assert_server_survives(process, "correct-token")

    conn, reply = auth_connect(socket_path, WRONG_TOKEN)
    try:
        assert reply == {"rpce_auth": {"status": "rejected"}}, reply
        assert read_socket_line(conn) == b"", "wrong-token connection stayed open"
    finally:
        conn.close()
    assert_server_survives(process, "wrong-token")

    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(socket_path)
    try:
        conn.sendall(b"not-json\n")
        line = read_socket_line(conn)
        assert line, "malformed-auth server closed before reply"
        msg = json.loads(line.decode())
        assert msg == {"rpce_auth": {"status": "rejected"}}, msg
        assert read_socket_line(conn) == b"", "malformed-auth connection stayed open"
    finally:
        conn.close()
    assert_server_survives(process, "malformed-auth")

    conn, reply = auth_connect(socket_path, "")
    try:
        assert reply == {"rpce_auth": {"status": "rejected"}}, reply
        assert read_socket_line(conn) == b"", "empty-token connection stayed open"
    finally:
        conn.close()
    assert_server_survives(process, "empty-token")

    conn, reply = auth_connect(socket_path, TOKEN)
    try:
        assert reply == {"rpce_auth": {"status": "accepted"}}, reply
        tools = initialize_and_list_tools(conn, "socket-auth-survival-smoke")
        assert tools == FULL_TOOLS, sorted(tools)
    finally:
        conn.close()
    assert_server_survives(process, "post-empty-token")

    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(socket_path)
    try:
        conn.sendall(json.dumps({
            "jsonrpc": "2.0",
            "id": 999,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "socket-auth-no-handshake-smoke", "version": "0"},
            },
        }).encode() + b"\n")
        line = read_socket_line(conn, timeout=12)
        if line:
            msg = json.loads(line.decode())
            assert msg == {"rpce_auth": {"status": "rejected"}}, msg
            assert read_socket_line(conn) == b"", "no-handshake connection stayed open after rejection"
    finally:
        conn.close()
    assert_server_survives(process, "no-handshake")

    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(socket_path)
    try:
        assert read_socket_line(conn, timeout=12) == b"", "timeout-auth connection stayed open"
    finally:
        conn.close()
    assert_server_survives(process, "timeout-auth")


def run_restricted_socket_scenario(socket_path, process):
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(socket_path)
    try:
        ids = itertools.count(1)
        rpc(conn, ids, "initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "socket-auth-restricted-smoke", "version": "0"},
        })
        notify(conn, "notifications/initialized")
        tools = {tool["name"] for tool in rpc(conn, ids, "tools/list")["tools"]}
        assert tools == DISCOVERY_TOOLS, sorted(tools)
        assert "agent_run" not in tools, sorted(tools)
        result, text = call_tool(conn, ids, "headless_status")
        assert not result.get("isError"), text
        status = result.get("structuredContent") or json.loads(text)
        assert status["mcp_exposure"]["current_transport"] == "socket", status
        assert status["mcp_exposure"]["current_exposure"] == "discovery_restricted", status
        assert "context_builder" not in status["mcp_exposure"]["available_tools"], status
        assert status["available_agent_tools"]["context_builder"] is False, status
        assert status["available_agent_tools"]["agent_run"] is False, status
        assert status["available_agent_tools"]["agent_manage"] is False, status
        assert status["available_agent_tools"]["oracle_send"] is False, status
        assert all("context_builder" not in call for call in status["suggested_first_tool_calls"]), status
        assert all("agent_run" not in call for call in status["suggested_first_tool_calls"]), status
        assert "full stdio" in status["available_agent_tools"]["guidance"], status
    finally:
        conn.close()
    assert_server_survives(process, "restricted-control")


def start_bridge(binary, socket_path, auth, token=TOKEN):
    env = dict(os.environ)
    env["RPCE_SOCKET_AUTH_TOKEN"] = token
    argv = [binary, "connect", "--socket", socket_path]
    if auth:
        argv.append("--auth")
    return subprocess.Popen(
        argv,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def bridge_rpc(process, ids, method, params=None):
    request_id = next(ids)
    process.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params or {},
    }) + "\n")
    process.stdin.flush()

    while True:
        line = process.stdout.readline()
        if not line:
            stderr = process.stderr.read()
            raise AssertionError(f"bridge closed stdout while waiting for {method}; stderr={stderr}")
        msg = json.loads(line)
        assert "rpce_auth" not in msg, f"auth frame leaked to stdout: {msg}"
        if msg.get("id") == request_id:
            assert "error" not in msg, f"{method} -> {msg['error']}"
            return msg["result"]


def bridge_notify(process, method, params=None):
    process.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
    }) + "\n")
    process.stdin.flush()


def bridge_tools(binary, socket_path, auth, token=TOKEN):
    process = start_bridge(binary, socket_path, auth, token)
    ids = itertools.count(1)
    try:
        bridge_rpc(process, ids, "initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "socket-auth-bridge-smoke", "version": "0"},
        })
        bridge_notify(process, "notifications/initialized")
        tools = {tool["name"] for tool in bridge_rpc(process, ids, "tools/list")["tools"]}
        process.stdin.close()
        process.wait(timeout=5)
        stderr = process.stderr.read()
        assert process.returncode == 0, f"bridge exited {process.returncode}; stderr={stderr}"
        assert "rpce_auth" not in stderr, stderr
        return tools
    finally:
        stop_process(process)


def run_missing_bridge_token(binary):
    env = dict(os.environ)
    env.pop("RPCE_SOCKET_AUTH_TOKEN", None)
    process = subprocess.Popen(
        [binary, "connect", "--socket", "/tmp/rpce-headless-missing-token.sock", "--auth"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    stdout, stderr = process.communicate("", timeout=5)
    assert process.returncode == 64, (process.returncode, stdout, stderr)
    assert stdout == "", stdout
    assert "rpce-headless connect: missing RPCE_SOCKET_AUTH_TOKEN" in stderr, stderr
    assert TOKEN not in stderr, stderr


def read_fake_line(conn):
    data = bytearray()
    while True:
        chunk = conn.recv(1)
        if not chunk:
            return bytes(data)
        if chunk == b"\n":
            return bytes(data)
        data.extend(chunk)


def fake_responder(socket_path, mode, ready):
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    server.listen(1)
    ready.set()
    conn, _ = server.accept()
    with conn, server:
        read_fake_line(conn)
        if mode == "rejected":
            conn.sendall(b'{"rpce_auth":{"status":"rejected"}}\n')
        elif mode == "malformed":
            conn.sendall(b"not-json\n")
        elif mode == "eof":
            return
        elif mode == "no_response":
            time.sleep(12)
        else:
            raise AssertionError(f"unknown fake responder mode: {mode}")


def run_fake_bridge_rejection(binary, tmp_path, mode):
    socket_path = str(tmp_path / f"fake-{mode}.sock")
    ready = threading.Event()
    thread = threading.Thread(target=fake_responder, args=(socket_path, mode, ready), daemon=True)
    thread.start()
    assert ready.wait(timeout=5), f"fake responder did not start for {mode}"

    process = start_bridge(binary, socket_path, auth=True)
    stdout, stderr = process.communicate("", timeout=15)
    assert process.returncode == 65, (mode, process.returncode, stdout, stderr)
    assert stdout == "", (mode, stdout)
    assert "rpce-headless connect: socket authentication rejected" in stderr, (mode, stderr)
    assert "rpce_auth" not in stdout, (mode, stdout)
    assert TOKEN not in stderr, (mode, stderr)
    thread.join(timeout=1)
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass


def run_bridge_scenarios(binary, full_socket, restricted_socket, tmp_path):
    full_tools = bridge_tools(binary, full_socket, auth=True)
    assert full_tools == FULL_TOOLS, sorted(full_tools)

    restricted_tools = bridge_tools(binary, restricted_socket, auth=False)
    assert restricted_tools == DISCOVERY_TOOLS, sorted(restricted_tools)

    run_missing_bridge_token(binary)
    for mode in ("rejected", "malformed", "eof", "no_response"):
        run_fake_bridge_rejection(binary, tmp_path, mode)


def main():
    global SMOKE_TMP
    parser = argparse.ArgumentParser(description="Smoke-test rpce-headless authenticated socket behavior.")
    parser.add_argument("binary")
    parser.add_argument("root", nargs="?")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="rpce-headless-socket-auth-") as tmp:
        SMOKE_TMP = tmp
        tmp_path = Path(tmp)
        root = Path(args.root) if args.root else tmp_path / "workspace"
        root.mkdir(parents=True, exist_ok=True)
        (root / "smoke.txt").write_text("hello socket auth smoke\n")

        run_cli_gate(args.binary, root, tmp_path)

        full_socket = str(tmp_path / "full.sock")
        restricted_socket = str(tmp_path / "restricted.sock")
        full_server = start_server(args.binary, root, full_socket, expose_all_tools=True)
        restricted_server = start_server(args.binary, root, restricted_socket, expose_all_tools=False)
        try:
            run_full_socket_scenarios(full_socket, full_server)
            run_restricted_socket_scenario(restricted_socket, restricted_server)
            run_bridge_scenarios(args.binary, full_socket, restricted_socket, tmp_path)
        finally:
            stop_process(full_server)
            stop_process(restricted_server)

    print("SOCKET AUTH SMOKE OK")


if __name__ == "__main__":
    main()
