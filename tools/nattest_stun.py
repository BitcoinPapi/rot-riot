#!/usr/bin/env python3
"""A tiny "address finder" (STUN server) for tools/nattest.sh.

It answers one question, the only one the game asks: "what address did my
message come from?" (STUN binding request, RFC 5389). Give it the addresses
to listen on:  nattest_stun.py 203.0.113.1 203.0.113.9
"""
import select
import socket
import struct
import sys

MAGIC = 0x2112A442
socks = []
for ip in sys.argv[1:]:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((ip, 3478))
    socks.append(s)
print("address finders listening on", ", ".join(sys.argv[1:]), flush=True)
while True:
    for s in select.select(socks, [], [])[0]:
        data, (ip, port) = s.recvfrom(2048)
        if len(data) < 20 or data[:2] != b"\x00\x01" or struct.unpack("!I", data[4:8])[0] != MAGIC:
            continue  # (the host's game also sends 1-byte and keep-alive packets around; only questions get answers)
        print("asked by %s:%d" % (ip, port), flush=True)
        number = struct.unpack("!I", socket.inet_aton(ip))[0]
        # XOR-MAPPED-ADDRESS: family IPv4, port and address scrambled with the magic number.
        field = struct.pack("!HHBBHI", 0x0020, 8, 0, 0x01, port ^ (MAGIC >> 16), number ^ MAGIC)
        s.sendto(struct.pack("!HHI", 0x0101, len(field), MAGIC) + data[8:20] + field, (ip, port))
