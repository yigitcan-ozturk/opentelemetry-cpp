#!/usr/bin/env python3
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import socket
import ssl
import sys
import threading

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 14317
CERT = "certs/cert.pem"
KEY = "certs/key.pem"

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(512)
print("listening on 127.0.0.1:%d" % PORT, flush=True)

def handle(conn):
    try:
        s = ctx.wrap_socket(conn, server_side=True)
        s.recv(1)
        s.close()
    except Exception:
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass

while True:
    try:
        c, _ = srv.accept()
    except Exception:
        break
    threading.Thread(target=handle, args=(c,), daemon=True).start()
