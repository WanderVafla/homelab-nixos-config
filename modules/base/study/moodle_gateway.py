"""Read-only gateway to the Moodle web service API for the Hermes agent.

The gateway holds the Moodle token, so the agent never sees it, and forwards only the
functions on the allowlist. A Moodle token can do everything the student can (submit work,
post in forums), so the allowlist is the boundary that keeps the agent read-only.

  GET /api/<function>?<params>    Moodle REST call, JSON response
  GET /file?url=<pluginfile url>  download a course file through the web service

Settings come from the environment: MOODLE_URL, MOODLE_ALLOWED_FUNCTIONS (space separated),
HOST and PORT. The token is the systemd credential "moodle-token".
"""

import json
import os
import socket
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MOODLE = os.environ["MOODLE_URL"].rstrip("/")
TOKEN_FILE = os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "moodle-token")
ALLOWED = set(os.environ["MOODLE_ALLOWED_FUNCTIONS"].split())
HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8070"))
PLACEHOLDER = "REPLACE_ME"
# Parameters the caller may not set: they would replace the token or the function name.
RESERVED = {"wstoken", "token", "wsfunction", "moodlewsrestformat"}
FILE_PREFIXES = (MOODLE + "/webservice/pluginfile.php/", MOODLE + "/pluginfile.php/")


def read_token():
    try:
        with open(TOKEN_FILE) as f:
            token = f.read().strip()
    except OSError:
        return None
    return None if token in ("", PLACEHOLDER) else token


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # The address belongs to the container's veth link, which appears only when the
        # container starts; freebind lets the gateway listen on it before that.
        self.socket.setsockopt(socket.IPPROTO_IP, socket.IP_FREEBIND, 1)
        super().server_bind()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
        token = read_token()
        if token is None:
            self.reply_json(503, {"error": "Moodle token is not set yet; ask the owner to add it"})
        elif parts.path.startswith("/api/"):
            self.call_api(token, parts.path[len("/api/"):], query)
        elif parts.path == "/file":
            self.download(token, dict(query).get("url", ""))
        else:
            self.reply_json(404, {"error": "use /api/<function>?<params> or /file?url=<pluginfile url>"})

    def call_api(self, token, function, query):
        if function not in ALLOWED:
            self.reply_json(403, {
                "error": f"{function} is not allowed; this gateway is read-only",
                "allowed": sorted(ALLOWED),
            })
            return
        params = [(k, v) for k, v in query if k not in RESERVED]
        params += [("wstoken", token), ("wsfunction", function), ("moodlewsrestformat", "json")]
        request = urllib.request.Request(
            MOODLE + "/webservice/rest/server.php",
            data=urllib.parse.urlencode(params).encode(),
        )
        self.forward(token, request)

    def download(self, token, url):
        if not url.startswith(FILE_PREFIXES):
            self.reply_json(400, {"error": f"url must start with {FILE_PREFIXES[0]}"})
            return
        url = url.replace(FILE_PREFIXES[1], FILE_PREFIXES[0], 1)
        parts = urllib.parse.urlsplit(url)
        query = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query) if k not in RESERVED]
        query.append(("token", token))
        self.forward(token, urllib.request.Request(parts._replace(query=urllib.parse.urlencode(query)).geturl()))

    def forward(self, token, request):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                status, headers, body = response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            status, headers, body = error.code, error.headers, error.read()
        except urllib.error.URLError as error:
            self.reply_json(502, {"error": f"Moodle is unreachable: {error.reason}"})
            return
        # Never hand the token back, even if Moodle echoes it in an error or a file URL.
        body = body.replace(token.encode(), b"[token]")
        self.send_response(status)
        for name in ("Content-Type", "Content-Disposition"):
            if headers.get(name):
                self.send_header(name, headers[name])
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def reply_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    Server((HOST, PORT), Handler).serve_forever()
