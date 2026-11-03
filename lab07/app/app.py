"""Tiny web app for Lab 07: says which pod answered and which version it runs."""
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
GREETING = os.environ.get("GREETING", "Hello")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, "ok\n")
        else:
            self._send(200, f"{GREETING} from {socket.gethostname()} (version {VERSION})\n")

    def _send(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        # one line per request on stdout, so `docker logs` / `kubectl logs` show it
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    print(f"listening on :{port}, version {VERSION}", flush=True)
    ThreadingHTTPServer(("", port), Handler).serve_forever()
