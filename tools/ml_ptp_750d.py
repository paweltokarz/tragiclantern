#!/usr/bin/env python3
import argparse
import os
import struct
import sys
from pathlib import Path

import usb.core
import usb.util

VID = 0x04A9
PID = 0x32A1

PTP_CMD = 1
PTP_DATA = 2
PTP_RESP = 3

OP_GET_DEVICE_INFO = 0x1001
OP_OPEN_SESSION = 0x1002
OP_CLOSE_SESSION = 0x1003
OP_CHDK = 0x9999

RC_OK = 0x2001

CHDK_VERSION = 0
CHDK_GET_MEMORY = 1
CHDK_TEMP_DATA = 4
CHDK_UPLOAD_FILE = 5
CHDK_DOWNLOAD_FILE = 6

def pack_container(ctype, code, tid, params=(), payload=b""):
    return struct.pack("<IHHI", 12 + 4 * len(params) + len(payload), ctype, code, tid) + b"".join(
        struct.pack("<I", p & 0xFFFFFFFF) for p in params
    ) + payload

def unpack_container(data):
    if len(data) < 12:
        raise RuntimeError("short PTP container: %d bytes" % len(data))
    length, ctype, code, tid = struct.unpack_from("<IHHI", data, 0)
    payload = bytes(data[12:length])
    params = []
    if ctype == PTP_RESP:
        for off in range(12, min(length, len(data)), 4):
            if off + 4 <= len(data):
                params.append(struct.unpack_from("<I", data, off)[0])
    return length, ctype, code, tid, payload, params

def connect(timeout):
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        raise RuntimeError("Canon EOS 750D USB device not found")

    cfg = dev.get_active_configuration()
    intf = None
    for candidate in cfg:
        if candidate.bInterfaceClass == 6:
            intf = candidate
            break
    if intf is None:
        raise RuntimeError("PTP interface class 6 not found")

    if dev.is_kernel_driver_active(intf.bInterfaceNumber):
        dev.detach_kernel_driver(intf.bInterfaceNumber)

    usb.util.claim_interface(dev, intf.bInterfaceNumber)

    ep_in = None
    ep_out = None
    for ep in intf:
        direction = usb.util.endpoint_direction(ep.bEndpointAddress)
        etype = usb.util.endpoint_type(ep.bmAttributes)
        if direction == usb.util.ENDPOINT_IN and etype == usb.util.ENDPOINT_TYPE_BULK:
            ep_in = ep
        elif direction == usb.util.ENDPOINT_OUT and etype == usb.util.ENDPOINT_TYPE_BULK:
            ep_out = ep

    if ep_in is None or ep_out is None:
        raise RuntimeError("PTP bulk endpoints not found")

    return dev, intf, ep_in, ep_out

class PTP:
    def __init__(self, timeout=5000, verbose=False):
        self.timeout = timeout
        self.verbose = verbose
        self.tid = 1
        self.dev = None
        self.intf = None
        self.ep_in = None
        self.ep_out = None

    def __enter__(self):
        self.dev, self.intf, self.ep_in, self.ep_out = connect(self.timeout)
        if self.verbose:
            print("connected: Canon EOS 750D PTP")
            print("interface=%d ep_in=0x%02x ep_out=0x%02x" % (
                self.intf.bInterfaceNumber,
                self.ep_in.bEndpointAddress,
                self.ep_out.bEndpointAddress,
            ))
        self.cmd(OP_GET_DEVICE_INFO, expect_data=True, label="GetDeviceInfo")
        rc, _params, _data = self.cmd(OP_OPEN_SESSION, params=(1,), label="OpenSession")
        if rc != RC_OK:
            raise RuntimeError("OpenSession failed: rc=0x%04x" % rc)
        rc, params, _data = self.cmd(OP_CHDK, params=(CHDK_VERSION,), label="CHDK Version")
        if rc != RC_OK:
            raise RuntimeError("CHDK Version failed: rc=0x%04x" % rc)
        if self.verbose:
            print("CHDK_VERSION params=%s" % ([hex(p) for p in params],))
        return self

    def __exit__(self, exc_type, exc, tb):
        try:
            if self.ep_out is not None and self.ep_in is not None:
                try:
                    self.cmd(OP_CLOSE_SESSION, label="CloseSession")
                except Exception as e:
                    if self.verbose:
                        print("CloseSession warning: %s" % e)
        finally:
            try:
                if self.dev is not None and self.intf is not None:
                    usb.util.release_interface(self.dev, self.intf.bInterfaceNumber)
            except Exception:
                pass
            if self.dev is not None:
                usb.util.dispose_resources(self.dev)

    def read_answer(self, expect_data=False):
        first = bytes(self.ep_in.read(1024 * 1024, timeout=self.timeout))
        length, ctype, code, tid, payload, params = unpack_container(first)
        if self.verbose:
            print("RX1 len=%d type=%d code=0x%04x tid=%d payload=%d params=%s" % (
                length, ctype, code, tid, len(payload), [hex(p) for p in params]
            ))

        if ctype == PTP_DATA:
            second = bytes(self.ep_in.read(4096, timeout=self.timeout))
            slen, sctype, scode, stid, spayload, sparams = unpack_container(second)
            if self.verbose:
                print("RX2 len=%d type=%d code=0x%04x tid=%d payload=%d params=%s" % (
                    slen, sctype, scode, stid, len(spayload), [hex(p) for p in sparams]
                ))
            return scode, sparams, payload

        if ctype == PTP_RESP:
            if expect_data:
                raise RuntimeError("expected data phase, got response rc=0x%04x params=%s" % (
                    code, [hex(p) for p in params]
                ))
            return code, params, payload

        raise RuntimeError("unexpected PTP container type %d" % ctype)

    def cmd(self, opcode, params=(), expect_data=False, label=""):
        tid = self.tid
        self.tid += 1
        if self.verbose:
            print("")
            print("TX %s op=0x%04x tid=%d params=%s" % (label, opcode, tid, [hex(p) for p in params]))
        self.ep_out.write(pack_container(PTP_CMD, opcode, tid, params=params), timeout=self.timeout)
        return self.read_answer(expect_data=expect_data)

    def cmd_data(self, opcode, params, data, label=""):
        tid = self.tid
        self.tid += 1
        if self.verbose:
            print("")
            print("TX %s op=0x%04x tid=%d params=%s data_len=%d" % (
                label, opcode, tid, [hex(p) for p in params], len(data)
            ))
        self.ep_out.write(pack_container(PTP_CMD, opcode, tid, params=params), timeout=self.timeout)
        self.ep_out.write(pack_container(PTP_DATA, opcode, tid, payload=data), timeout=self.timeout)
        return self.read_answer(expect_data=False)

    def upload(self, local, remote):
        payload = Path(local).read_bytes()
        remote_b = remote.encode("utf-8")
        data = struct.pack("<I", len(remote_b)) + remote_b + payload
        rc, params, _ = self.cmd_data(OP_CHDK, (CHDK_UPLOAD_FILE,), data, label="UploadFile")
        if rc != RC_OK:
            raise RuntimeError("UploadFile failed: rc=0x%04x params=%s" % (rc, [hex(p) for p in params]))
        return len(payload), params

    def download(self, remote, local):
        remote_b = remote.encode("utf-8")
        rc, params, _ = self.cmd_data(OP_CHDK, (CHDK_TEMP_DATA, 0), remote_b, label="TempData")
        if rc != RC_OK:
            raise RuntimeError("TempData failed: rc=0x%04x params=%s" % (rc, [hex(p) for p in params]))

        rc, params, data = self.cmd(OP_CHDK, (CHDK_DOWNLOAD_FILE,), expect_data=True, label="DownloadFile")
        if rc != RC_OK:
            raise RuntimeError("DownloadFile failed: rc=0x%04x params=%s" % (rc, [hex(p) for p in params]))
        out = Path(local)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        reported = params[0] if params else len(data)
        return len(data), reported

    def getmem(self, addr, size):
        rc, params, data = self.cmd(OP_CHDK, (CHDK_GET_MEMORY, addr, size), expect_data=True, label="GetMemory")
        if rc != RC_OK:
            raise RuntimeError("GetMemory failed: rc=0x%04x params=%s" % (rc, [hex(p) for p in params]))
        return data[:size]

def cmd_info(args):
    with PTP(timeout=args.timeout, verbose=args.verbose):
        print("OK: PTP CHDK bridge is reachable")

def cmd_put(args):
    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        n, params = ptp.upload(args.local, args.remote)
    print("PUT_OK local=%s remote=%s bytes=%d params=%s" % (args.local, args.remote, n, [hex(p) for p in params]))

def cmd_get(args):
    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        n, reported = ptp.download(args.remote, args.local)
    print("GET_OK remote=%s local=%s bytes=%d reported=%d" % (args.remote, args.local, n, reported))

def cmd_getmem(args):
    if args.size <= 0 or args.size > 1024 * 1024:
        raise RuntimeError("unsafe getmem size; use 1..1048576")
    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        data = ptp.getmem(int(args.addr, 0), args.size)
    sys.stdout.buffer.write(data)

def main():
    ap = argparse.ArgumentParser(description="Minimal ML/CHDK PTP client for Canon EOS 750D experiments.")
    ap.add_argument("--timeout", type=int, default=5000)
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("info")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("put")
    p.add_argument("local")
    p.add_argument("remote")
    p.set_defaults(func=cmd_put)

    p = sub.add_parser("get")
    p.add_argument("remote")
    p.add_argument("local")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("getmem")
    p.add_argument("addr")
    p.add_argument("size", type=int)
    p.set_defaults(func=cmd_getmem)

    args = ap.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
