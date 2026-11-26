#!/usr/bin/env python3
"""Fail CI if the Android APK is missing plugin native libraries.

The 0.9.x super_clipboard/super_native_extensions stack loads Rust libraries
through JNI. A build that silently omits them will install but crash on
startup with UnsatisfiedLinkError. Check the APK before publishing.
"""

from __future__ import annotations

import sys
import zipfile

ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
LIBS = (
    "libsuper_native_extensions.so",
    "libirondash_engine_context_native.so",
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_android_apk.py <apk>")
        return 2
    apk = sys.argv[1]
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
    missing = [
        f"lib/{abi}/{lib}"
        for abi in ABIS
        for lib in LIBS
        if f"lib/{abi}/{lib}" not in names
    ]
    if missing:
        print("APK is missing required native libraries:")
        for name in missing:
            print(" -", name)
        return 1
    print("APK native libraries verified:")
    for abi in ABIS:
        for lib in LIBS:
            print(f" - lib/{abi}/{lib}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
