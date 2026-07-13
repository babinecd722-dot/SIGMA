#!/usr/bin/env python3
"""Patch official launcher to load libresolution.so after update-manager."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


SNIPPET = """\
.method static constructor <clinit>()V
    .locals 1

    const-string/jumbo v0, "update-manager"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const-string v0, "resolution"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const-string v0, "blackrussia-client"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    return-void
.end method
"""


def find_jnilib(smali_root: Path) -> Path:
    hits = list(smali_root.rglob("JNILib.smali"))
    for h in hits:
        if "blackhub/bronline/game/core/JNILib.smali" in str(h).replace("\\", "/"):
            return h
    raise SystemExit("JNILib.smali not found")


def patch_clinit(text: str) -> str:
    start = text.find(".method static constructor <clinit>()V")
    if start < 0:
        raise SystemExit("clinit not found")
    end = text.find(".end method", start)
    if end < 0:
        raise SystemExit("clinit end not found")
    end += len(".end method")
    return text[:start] + SNIPPET.strip() + "\n\n" + text[end + 1 :]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True, help="official launcher.apk")
    ap.add_argument("--so", required=True, help="path to libresolution.so (arm64-v8a)")
    ap.add_argument("--out", required=True, help="output apk path")
    ap.add_argument("--workdir", default="/tmp/resolution-inject")
    args = ap.parse_args()

    apk = Path(args.apk)
    so = Path(args.so)
    out = Path(args.out)
    work = Path(args.workdir)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    decoded = work / "decoded"
    subprocess.check_call(["apktool", "d", "-f", str(apk), "-o", str(decoded)])

    jni = find_jnilib(decoded)
    jni.write_text(patch_clinit(jni.read_text(encoding="utf-8", errors="replace")), encoding="utf-8")

    libdir = decoded / "lib" / "arm64-v8a"
    libdir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(so, libdir / "libresolution.so")

    # also drop fab asset for optional java overlay
    assets = decoded / "assets" / "resolution"
    assets.mkdir(parents=True, exist_ok=True)

    built = work / "unsigned.apk"
    subprocess.check_call(["apktool", "b", str(decoded), "-o", str(built)])

    # zip-align + sign left to user (apksigner / uber-apk-signer)
    shutil.copy2(built, out)
    print(f"wrote {out}")
    print("sign with: apksigner sign --ks your.keystore --out signed.apk", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
