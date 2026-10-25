#!/usr/bin/env python3
"""Print the size and SHA-256 of an APK's v2 signing certificate.

KernelSU-based kernels (FinaSU included) trust a manager APK by the length
and SHA-256 of the first certificate in its APK Signature Scheme v2 block,
so the kernel must be built with these two values.
Usage: apk_cert.py <file.apk>  ->  prints "0x<size> <sha256>"
"""
import hashlib
import struct
import sys

V2_BLOCK_ID = 0x7109871A


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def lv(b, o):
    """Read a uint32 length-prefixed value at o; return (value, next offset)."""
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def main(path):
    data = open(path, "rb").read()
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        sys.exit("not a zip file")
    cd_offset = u32(data, eocd + 16)
    if data[cd_offset - 16:cd_offset] != b"APK Sig Block 42":
        sys.exit("no APK signing block (v1-only APK?)")
    block_size = u64(data, cd_offset - 24)
    start = cd_offset - block_size - 8
    pairs, end = start + 8, cd_offset - 24
    o = pairs
    while o < end:
        n = u64(data, o)
        pid = u32(data, o + 8)
        if pid == V2_BLOCK_ID:
            v = data[o + 12:o + 8 + n]
            signers, _ = lv(v, 0)
            signer, _ = lv(signers, 0)
            signed_data, _ = lv(signer, 0)
            _digests, p = lv(signed_data, 0)
            certs, _ = lv(signed_data, p)
            cert, _ = lv(certs, 0)
            print("0x%04x %s" % (len(cert), hashlib.sha256(cert).hexdigest()))
            return
        o += 8 + n
    sys.exit("no v2 signature block")


if __name__ == "__main__":
    main(sys.argv[1])
