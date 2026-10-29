"""Loopback-only, manual OTP bridge for the opt-in Android Gmail QA harness.

No mailbox access. OTPs remain in memory and are removed after one retrieval.
Start with --config .local/f3-qa.json; use authenticated /status and /code locally.
"""
import argparse
import hmac
import json
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('--config', required=True)
parser.add_argument('--port', type=int, default=8089)
args = parser.parse_args()
with open(args.config, encoding='utf-8-sig') as source:
    config = json.load(source)
key = config['QA_F3_BRIDGE_KEY']
allowed = {config[f'QA_F3_{name}'] for name in ('CUSTOMER1', 'CUSTOMER2', 'STAFF')}
pending = {}
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log codes, query strings, or authorization headers.

    def reply(self, status, data):
        payload = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)

    def handle_request(self):
        if not hmac.compare_digest(self.headers.get('X-Qa-Bridge', ''), key):
            return self.reply(403, {})
        route = urlsplit(self.path)
        with lock:
            for identifier in list(pending):
                if time.monotonic() - pending[identifier]['created'] > 300:
                    del pending[identifier]
            if self.command == 'GET' and route.path == '/status':
                return self.reply(200, [
                    {'id': identifier, 'email': item['email'], 'purpose': item['purpose'],
                     'ready': item.get('code') is not None}
                    for identifier, item in pending.items()
                ])
            if self.command == 'GET' and route.path == '/poll':
                identifier = parse_qs(route.query).get('id', [''])[0]
                item = pending.get(identifier)
                if item is None:
                    return self.reply(404, {})
                if 'code' not in item:
                    return self.reply(200, {})
                del pending[identifier]
                return self.reply(200, {'code': item['code']})
            if self.command != 'POST':
                return self.reply(404, {})
            length = int(self.headers.get('Content-Length', '0'))
            if length > 2048:
                return self.reply(400, {})
            data = json.loads(self.rfile.read(length))
            if route.path == '/request':
                if data.get('email') not in allowed or data.get('purpose') not in ('SIGNUP', 'LOGIN'):
                    return self.reply(400, {})
                identifier = secrets.token_hex(12)
                pending[identifier] = {**data, 'created': time.monotonic()}
                return self.reply(200, {'id': identifier})
            if route.path == '/code':
                item = pending.get(data.get('id'))
                if item is None or not re.fullmatch(r'[0-9]{6}', data.get('code', '')):
                    return self.reply(400, {})
                item['code'] = data['code']
                return self.reply(200, {'accepted': True})
            return self.reply(404, {})

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()


print('Manual Gmail QA bridge listening on loopback.', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
