import http.client
import importlib.util
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location('nomad_proxy', Path(__file__).resolve().parents[2] / 'scripts/__nomad_ollama_proxy.py')
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class Upstream(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.respond()

    def do_DELETE(self):
        self.respond()

    def respond(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.server.calls.append((self.command, self.path, body))
        if self.path == '/api/tags':
            data = json.dumps({'models': [{'name': 'gpt-oss:20b'}, {'name': 'nomic-embed-text:v1.5'}]}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(self.server.status)
        self.send_header('Connection', 'close')
        if self.server.declared_length is not None:
            self.send_header('Content-Length', str(self.server.declared_length))
        self.end_headers()
        self.wfile.write(self.server.first)
        self.wfile.flush()
        if self.server.wait:
            self.server.wait.wait(2)
        if self.server.second:
            self.wfile.write(self.server.second)
            self.wfile.flush()
        self.close_connection = True


@pytest.fixture
def servers():
    running = []
    def make(handler):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
        server.daemon_threads = True
        server.calls, server.status, server.first, server.second, server.wait = [], 200, b'first', b'', None
        server.declared_length = None
        threading.Thread(target=server.serve_forever, daemon=True).start()
        running.append(server)
        return server
    yield make
    for server in running:
        server.shutdown()
        server.server_close()


def url(server):
    return 'http://127.0.0.1:%d' % server.server_port


def start_proxy(servers, remote, local):
    server = servers(proxy.Proxy)
    server.remote_url = remote
    server.local_url = url(local)
    server.local_container = 'unused'
    return server


def request(server, path='/api/chat', body=b'{"model":"gpt-oss:20b"}', method='POST'):
    conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=4)
    conn.request(method, path, body=body, headers={'Content-Type': 'application/json'})
    return conn, conn.getresponse()


def test_remote_preferred(servers):
    remote, local = servers(Upstream), servers(Upstream)
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server)
    assert response.status == 200 and response.read() == b'first'
    assert len(remote.calls) == 1 and local.calls == []
    conn.close()


def test_unreachable_remote_uses_local_and_maps_missing_model(servers):
    local = servers(Upstream)
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    server = start_proxy(servers, f'http://127.0.0.1:{port}', local)
    conn, response = request(server, body=b'{"model":"other:latest","messages":[]}')
    assert response.status == 200 and response.read() == b'first'
    assert json.loads(local.calls[-1][2])['model'] == 'gpt-oss:20b'
    conn.close()


def test_503_falls_back_and_keeps_available_model(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.status = 503
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server, path='/api/embed', body=b'{"model":"nomic-embed-text:v1.5","input":"x"}')
    assert response.status == 200 and response.read() == b'first'
    assert json.loads(local.calls[-1][2])['model'] == 'nomic-embed-text:v1.5'
    conn.close()


def test_mutation_is_not_replayed(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.status = 503
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server, path='/api/pull')
    assert response.status == 503
    response.read()
    assert local.calls == []
    conn.close()


def test_stream_is_forwarded_before_upstream_finishes(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.wait = threading.Event()
    remote.second = b'second'
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server)
    assert response.read(5) == b'first'
    assert not remote.wait.is_set()
    remote.wait.set()
    assert response.read() == b'second'
    conn.close()


def test_interrupted_stream_is_not_retried(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.declared_length = 20
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server)
    assert response.read() == b'first'
    assert len(remote.calls) == 1 and local.calls == []
    conn.close()
