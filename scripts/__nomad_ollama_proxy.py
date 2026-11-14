#!/usr/bin/env python3
"""Remote-first Ollama proxy for the NOMAD offline library."""
import argparse
import http.client
import json
import socket
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PROFILE = Path.home() / '.local/share/nomad-setup/remote-ollama.json'
RETRYABLE_STATUS = {502, 503, 504}
SAFE_GET = {'/', '/api/tags', '/api/ps', '/api/version', '/v1/models'}
SAFE_POST = {'/api/chat', '/api/generate', '/api/show', '/api/embed',
             '/api/embeddings', '/v1/chat/completions', '/v1/completions', '/v1/embeddings'}
CHAT_POST = {'/api/chat', '/api/generate', '/api/show', '/v1/chat/completions', '/v1/completions'}
EMBED_POST = {'/api/embed', '/api/embeddings', '/v1/embeddings'}
HOP_HEADERS = {'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
               'te', 'trailer', 'transfer-encoding', 'upgrade', 'host', 'content-length'}


def connect(url, timeout):
    parsed = urlsplit(url)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.path not in ('', '/'):
        raise ValueError('upstream must be an HTTP(S) origin')
    cls = http.client.HTTPSConnection if parsed.scheme == 'https' else http.client.HTTPConnection
    return cls(parsed.hostname, parsed.port, timeout=timeout)


def local_url(container):
    # NOMAD can stop the local container when a remote endpoint is configured.
    subprocess.run(['docker', 'start', container], check=True, capture_output=True, timeout=20)
    result = subprocess.run(['docker', 'inspect', '--format',
                             '{{(index .NetworkSettings.Networks "project-nomad_default").IPAddress}}',
                             container], check=True, capture_output=True, text=True, timeout=10)
    address = result.stdout.strip()
    socket.inet_aton(address)
    return f'http://{address}:11434'


def available_models(url):
    conn = connect(url, 5)
    try:
        conn.request('GET', '/api/tags')
        response = conn.getresponse()
        if response.status != 200:
            raise OSError('local model list unavailable')
        return {item['name'] for item in json.load(response).get('models', [])}
    finally:
        conn.close()


def local_body(path, body, url):
    if path not in CHAT_POST | EMBED_POST or not body:
        return body
    data = json.loads(body)
    model = data.get('model')
    if not isinstance(model, str):
        return body
    names = available_models(url)
    if model not in names and f'{model}:latest' not in names:
        data['model'] = 'nomic-embed-text:v1.5' if path in EMBED_POST else 'gpt-oss:20b'
        return json.dumps(data).encode()
    return body


class Proxy(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, format, *args):
        # Do not log chat prompts or URLs containing query parameters.
        pass

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def do_DELETE(self):
        self.forward()

    def forward(self):
        path = urlsplit(self.path).path
        safe = (self.command == 'GET' and path in SAFE_GET) or (self.command == 'POST' and path in SAFE_POST)
        if self.headers.get('Transfer-Encoding'):
            self.send_error(400, 'Chunked request bodies are unsupported')
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 0 or size > 32 * 1024 * 1024:
                raise ValueError()
            body = self.rfile.read(size)
        except ValueError:
            self.send_error(400, 'Invalid content length')
            return
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
        conn = None
        headers_sent = False
        try:
            try:
                conn, response = self.upstream(self.server.remote_url, body, headers)
                if safe and response.status in RETRYABLE_STATUS:
                    conn.close()
                    conn = None
                    raise OSError('upstream unavailable')
            except (OSError, http.client.HTTPException, ValueError):
                if not safe:
                    raise
                if conn:
                    conn.close()
                url = self.server.local_url or local_url(self.server.local_container)
                body = local_body(path, body, url)
                conn, response = self.upstream(url, body, headers, timeout=30)
            # From here on a retry could duplicate a request or splice two streams.
            if conn.sock:
                conn.sock.settimeout(None)
            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in HOP_HEADERS:
                    self.send_header(key, value)
            self.send_header('Connection', 'close')
            self.end_headers()
            headers_sent = True
            self.close_connection = True
            while True:
                chunk = response.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (OSError, ValueError, http.client.HTTPException, subprocess.SubprocessError, json.JSONDecodeError) as exc:
            if not headers_sent:
                self.send_error(502, 'Ollama unavailable')
            print(f'NOMAD Ollama proxy: {type(exc).__name__}', file=sys.stderr)
        finally:
            if conn:
                conn.close()

    def upstream(self, url, body, headers, timeout=5):
        conn = connect(url, timeout)
        try:
            conn.connect()
            # Model loading may take longer than connecting to the server.
            conn.sock.settimeout(120)
            conn.request(self.command, self.path, body=body if self.command != 'GET' else None, headers=headers)
            return conn, conn.getresponse()
        except Exception:
            conn.close()
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remote-profile', type=Path, default=PROFILE)
    parser.add_argument('--remote-url')
    parser.add_argument('--local-container', default='nomad_ollama')
    parser.add_argument('--local-url', help='local Ollama origin, for testing or a fixed endpoint')
    parser.add_argument('--listen', default='10.114.0.1:11437')
    args = parser.parse_args()
    remote = args.remote_url or json.loads(args.remote_profile.read_text())['url']
    connect(remote, 5).close()  # validate origin before accepting requests
    if args.local_url:
        connect(args.local_url, 5).close()
    host, port = args.listen.rsplit(':', 1)
    server = ThreadingHTTPServer((host, int(port)), Proxy)
    server.remote_url, server.local_url, server.local_container = remote, args.local_url, args.local_container
    server.serve_forever()


if __name__ == '__main__':
    main()
