#!/usr/bin/env python3
"""Inject libresolution.so into official launcher without apktool resource rebuild.

Strategy:
  1) baksmali original classes4.dex
  2) patch only JNILib.<clinit> to load resolution AFTER blackrussia-client
  3) smali → replace classes4.dex in zip
  4) add lib/arm64-v8a/libresolution.so
  5) drop META-INF (caller signs)
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


CLINIT = """\
.method static constructor <clinit>()V
    .registers 1

    const-string/jumbo v0, "update-manager"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const-string v0, "blackrussia-client"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const-string v0, "resolution"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    return-void
.end method
"""


def patch_clinit(text: str) -> str:
    start = text.find(".method static constructor <clinit>()V")
    if start < 0:
        raise SystemExit("clinit not found in JNILib.smali")
    end = text.find(".end method", start)
    if end < 0:
        raise SystemExit("clinit end not found")
    end += len(".end method")
    return text[:start] + CLINIT.strip() + "\n\n" + text[end + 1 :]


def find_jnilib(smali_root: Path) -> Path:
    for h in smali_root.rglob("JNILib.smali"):
        if "blackhub/bronline/game/core/JNILib.smali" in str(h).replace("\\", "/"):
            return h
    raise SystemExit("JNILib.smali not found")


def which_or(name: str) -> str:
    p = shutil.which(name)
    if not p:
        raise SystemExit(f"{name} not found on PATH")
    return p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True)
    ap.add_argument("--so", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workdir", default="/tmp/resolution-inject-zip")
    args = ap.parse_args()

    baksmali = which_or("baksmali")
    smali = which_or("smali")

    apk = Path(args.apk)
    so = Path(args.so)
    out = Path(args.out)
    work = Path(args.workdir)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    # Extract classes4.dex from original
    with zipfile.ZipFile(apk, "r") as z:
        names = z.namelist()
        dex_name = "classes4.dex"
        if dex_name not in names:
            # locate JNILib dex by scanning
            dex_name = None
            for n in names:
                if not n.startswith("classes") or not n.endswith(".dex"):
                    continue
                data = z.read(n)
                if b"blackrussia-client" in data and b"update-manager" in data:
                    dex_name = n
                    break
            if not dex_name:
                raise SystemExit("JNILib dex not found")
        dex_bytes = z.read(dex_name)

    orig_dex = work / "orig.dex"
    orig_dex.write_bytes(dex_bytes)
    smali_dir = work / "smali"
    subprocess.check_call([baksmali, "d", "-o", str(smali_dir), str(orig_dex)])

    jni = find_jnilib(smali_dir)
    jni.write_text(patch_clinit(jni.read_text(encoding="utf-8", errors="replace")), encoding="utf-8")
    text = jni.read_text(encoding="utf-8")
    if "resolution" not in text or "blackrussia-client" not in text:
        raise SystemExit("patch failed validation")

    new_dex = work / "patched.dex"
    subprocess.check_call([smali, "a", "-o", str(new_dex), str(smali_dir)])

    # Stage apk contents
    stage = work / "apk"
    stage.mkdir()
    with zipfile.ZipFile(apk, "r") as zin:
        zin.extractall(stage)
        infos = {i.filename: i for i in zin.infolist()}

    # Replace dex + add so
    (stage / dex_name).write_bytes(new_dex.read_bytes())
    libdir = stage / "lib" / "arm64-v8a"
    libdir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(so, libdir / "libresolution.so")

    # Remove signatures
    meta = stage / "META-INF"
    if meta.exists():
        shutil.rmtree(meta)

    unsigned = work / "unsigned.apk"
    with zipfile.ZipFile(unsigned, "w") as zout:
        for path in sorted(stage.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(stage).as_posix()
            if rel.startswith("META-INF/"):
                continue
            compress = zipfile.ZIP_DEFLATED
            if rel in infos:
                compress = infos[rel].compress_type
            if rel.endswith((".so", ".arsc", ".ogg", ".mp3", ".wav")):
                compress = zipfile.ZIP_STORED
            zi = zipfile.ZipInfo(rel)
            zi.compress_type = compress
            zout.writestr(zi, path.read_bytes())

    shutil.copy2(unsigned, out)
    print(f"wrote {out}")
    print(f"patched {dex_name}; load order: update-manager -> blackrussia-client -> resolution")
    return 0


if __name__ == "__main__":
    sys.exit(main())
