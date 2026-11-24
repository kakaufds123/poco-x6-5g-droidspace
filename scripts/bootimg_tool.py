#!/usr/bin/env python3
"""Ferramenta mínima para boot.img header v4 (Android 13+ / GKI).

Comandos:
  info     BOOT                       mostra tamanhos e versão do kernel
  release  BOOT|IMAGE                 imprime só a versão (uname -r) do kernel
  kernel   BOOT OUT                   extrai o kernel (Image)
  config   BOOT OUT                   extrai o .config embutido (IKCONFIG)
  repack   BOOT IMAGE OUT             troca o kernel do BOOT pelo IMAGE
"""
import re
import struct
import sys
import zlib

PAGE = 4096


def die(msg):
    sys.exit(f"ERRO: {msg}")


def al(x):
    return (x + PAGE - 1) // PAGE * PAGE


def parse(d):
    if d[:8] != b"ANDROID!":
        die("não é um boot.img Android (magic ANDROID! ausente)")
    ks, rs, _osv, _hs = struct.unpack("<IIII", d[8:24])
    ver = struct.unpack("<I", d[40:44])[0]
    if ver != 4:
        die(f"boot.img header v{ver}; esta ferramenta só suporta v4")
    sig = struct.unpack("<I", d[1580:1584])[0]
    ko = PAGE
    ro = ko + al(ks)
    return {
        "ks": ks, "rs": rs, "sig": sig,
        "kernel": d[ko:ko + ks],
        "ramdisk": d[ro:ro + rs],
    }


def kernel_release(kernel):
    m = re.search(rb"Linux version (\d+\.\d+\.\d+\S*)", kernel)
    if not m:
        die("string 'Linux version' não encontrada (kernel comprimido?)")
    return m.group(1).decode()


def load_kernel_any(path):
    d = open(path, "rb").read()
    return parse(d)["kernel"] if d[:8] == b"ANDROID!" else d


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd, src = sys.argv[1], sys.argv[2]

    if cmd == "release":
        print(kernel_release(load_kernel_any(src)))
        return

    d = open(src, "rb").read()
    h = parse(d)

    if cmd == "info":
        print(f"kernel   : {h['ks']} bytes, magic {h['kernel'][:2]!r}")
        print(f"ramdisk  : {h['rs']} bytes")
        print(f"assinatura GKI: {h['sig']} bytes")
        print(f"release  : {kernel_release(h['kernel'])}")
    elif cmd == "kernel":
        if h["kernel"][:2] != b"MZ":
            die("kernel do boot.img não é um Image arm64 sem compressão")
        open(sys.argv[3], "wb").write(h["kernel"])
    elif cmd == "config":
        k = h["kernel"]
        i = k.find(b"IKCFG_ST")
        j = k.find(b"IKCFG_ED")
        if i < 0 or j < 0:
            die("kernel sem IKCONFIG embutido; forneça um .config manualmente")
        cfg = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(k[i + 8:j])
        open(sys.argv[3], "wb").write(cfg)
    elif cmd == "repack":
        new_kernel = open(sys.argv[3], "rb").read()
        out = sys.argv[4]
        if new_kernel[:2] != b"MZ":
            die("o novo kernel precisa ser um Image arm64 sem compressão")
        hdr = bytearray(d[:PAGE])
        struct.pack_into("<I", hdr, 8, len(new_kernel))
        struct.pack_into("<I", hdr, 1580, 0)  # assinatura GKI antiga deixa de valer
        blob = bytes(hdr)
        blob += new_kernel + b"\0" * (al(len(new_kernel)) - len(new_kernel))
        blob += h["ramdisk"] + b"\0" * (al(h["rs"]) - h["rs"])
        open(out, "wb").write(blob)
        print(f"ok: {out} ({len(blob)} bytes), kernel novo {len(new_kernel)} bytes")
    else:
        die(f"comando desconhecido: {cmd}")


if __name__ == "__main__":
    main()
