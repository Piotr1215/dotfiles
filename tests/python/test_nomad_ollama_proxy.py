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
        if self.path == '/api/version':
            if self.server.blackhole:
                self.server.blackhole.wait(6)
                return
            data = b'{"version":"test"}'
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.server.header_delay:
            time.sleep(self.server.header_delay)
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
        server.blackhole = None
        server.header_delay = 0
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
    conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=8)
    conn.request(method, path, body=body, headers={'Content-Type': 'application/json'})
    return conn, conn.getresponse()


def test_remote_preferred(servers):
    remote, local = servers(Upstream), servers(Upstream)
    server = start_proxy(servers, url(remote), local)
    conn, response = request(server)
    assert response.status == 200 and response.read() == b'first'
    assert [call[1] for call in remote.calls] == ['/api/version', '/api/chat'] and local.calls == []
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
    assert [call[1] for call in remote.calls] == ['/api/version', '/api/chat'] and local.calls == []
    conn.close()


def test_blackholed_remote_falls_back_within_health_timeout(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.blackhole = threading.Event()
    server = start_proxy(servers, url(remote), local)
    before = time.monotonic()
    conn, response = request(server)
    elapsed = time.monotonic() - before
    assert response.status == 200 and response.read() == b'first'
    assert elapsed < 5
    assert [call[1] for call in remote.calls] == ['/api/version']
    assert local.calls[-1][1] == '/api/chat'
    remote.blackhole.set()
    conn.close()


def test_healthy_remote_allows_slow_generation_headers(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.header_delay = 3.2
    server = start_proxy(servers, url(remote), local)
    before = time.monotonic()
    conn, response = request(server)
    assert response.status == 200 and response.read() == b'first'
    assert time.monotonic() - before >= 3
    assert [call[1] for call in remote.calls] == ['/api/version', '/api/chat']
    assert local.calls == []
    conn.close()


def test_blackholed_metadata_falls_back_within_timeout(servers):
    remote, local = servers(Upstream), servers(Upstream)
    remote.blackhole = threading.Event()
    server = start_proxy(servers, url(remote), local)
    before = time.monotonic()
    conn, response = request(server, path='/api/version', body=None, method='GET')
    assert response.status == 200
    assert json.loads(response.read()) == {'version': 'test'}
    assert time.monotonic() - before < 5
    assert [call[1] for call in remote.calls] == ['/api/version']
    assert [call[1] for call in local.calls] == ['/api/version']
    remote.blackhole.set()
    conn.close()


def test_server_binds_without_dns(monkeypatch):
    def reject_dns(*args):
        raise AssertionError('offline bind attempted DNS lookup')

    monkeypatch.setattr(socket, 'getfqdn', reject_dns)
    server = proxy.OfflineHTTPServer(('127.0.0.1', 0), proxy.Proxy)
    try:
        assert server.server_name == '127.0.0.1'
        assert server.server_port > 0
        assert server.socket.getsockname()[1] == server.server_port
        assert server.socket.getsockopt(socket.SOL_SOCKET, socket.SO_ACCEPTCONN) == 1
    finally:
        server.server_close()
