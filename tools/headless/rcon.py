"""Minimal Source RCON client, enough to drive a headless Factorio server."""

import socket
import struct

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2


class RconError(Exception):
    pass


class Rcon:
    def __init__(self, host, port, password, timeout=30.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.next_id = 1
        request_id = self._send(SERVERDATA_AUTH, password)
        # Some servers send an empty RESPONSE_VALUE before the AUTH_RESPONSE.
        while True:
            response_id, response_type, _ = self._recv()
            if response_type == 2:
                if response_id == -1 or response_id != request_id:
                    raise RconError("RCON authentication failed")
                return

    def _send(self, kind, body):
        request_id = self.next_id
        self.next_id += 1
        payload = struct.pack("<ii", request_id, kind) + body.encode("utf-8") + b"\x00\x00"
        self.sock.sendall(struct.pack("<i", len(payload)) + payload)
        return request_id

    def _recv_exact(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise RconError("RCON connection closed")
            data += chunk
        return data

    def _recv(self):
        (length,) = struct.unpack("<i", self._recv_exact(4))
        packet = self._recv_exact(length)
        response_id, response_type = struct.unpack("<ii", packet[:8])
        return response_id, response_type, packet[8:-2].decode("utf-8", errors="replace")

    def command(self, text):
        """Run a console command and return its output (rcon.print output for /sc)."""
        request_id = self._send(SERVERDATA_EXECCOMMAND, text)
        while True:
            response_id, _, body = self._recv()
            if response_id == request_id:
                return body

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass
