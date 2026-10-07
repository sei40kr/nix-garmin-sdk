"""Open a TLS connection through GIO's default TLS backend; exit 0 on success."""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

host, port = sys.argv[1], int(sys.argv[2])

backend = Gio.TlsBackend.get_default()
print("TLS backend:", type(backend).__name__, "supports TLS:", backend.supports_tls())
if not backend.supports_tls():
    sys.exit(2)

client = Gio.SocketClient.new()
client.set_tls(True)
try:
    conn = client.connect_to_host(host, port, None)
    conn.get_output_stream().write_all(b"GET / HTTP/1.0\r\n\r\n", None)
    print("handshake ok")
except GLib.Error as e:
    print("handshake failed:", e.message)
    sys.exit(1)
