#!/usr/bin/env python3
"""Patch CargoKit for Gradle 9 (Flutter 3.50 + super_native_extensions 0.9.x).

The Android builds of `super_native_extensions` and `irondash_engine_context`
bundle an old CargoKit Gradle script that calls the removed `Project.exec`
API. This script updates the copies in the local pub cache. It is a build
environment compatibility patch, not an application logic change.

Usage:
    python scripts/android_gradle9_compat.py

Run once after `flutter pub get`. Re-running is safe. Android build only.
"""

from __future__ import annotations

import os
from pathlib import Path


def pub_cache() -> Path:
    explicit = os.environ.get("PUB_CACHE")
    if explicit:
        return Path(explicit)
    local = os.environ.get("LOCALAPPDATA")
    if os.name == "nt" and local:
        return Path(local) / "Pub" / "Cache"
    return Path.home() / ".pub-cache"


def find_package(hosted: Path, name: str) -> Path | None:
    candidates = sorted(hosted.glob(f"{name}-*"), key=lambda p: p.name)
    for candidate in reversed(candidates):
        if (candidate / "cargokit" / "gradle" / "plugin.gradle").exists():
            return candidate
    return None


def patch(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text

    text = text.replace(
        "project.exec {\n                commandLine 'chmod', '+x', path\n            }",
        "project.providers.exec {\n                commandLine 'chmod', '+x', path\n            }.result.get()",
    )
    text = text.replace(
        "project.exec {\n            executable path",
        "project.providers.exec {\n            executable path",
    )
    text = text.replace(
        "environment \"CARGOKIT_JAVA_HOME\", System.properties['java.home']\n        }",
        "environment \"CARGOKIT_JAVA_HOME\", System.properties['java.home']\n        }.result.get()",
    )
    text = text.replace(
        'def path = Paths.get(new File(pluginFile).parent, "..", executableName);',
        'def path = Paths.get(new File(pluginFile).parent, "..", executableName).toString()',
    )
    text = text.replace(
        "def manifestDir = Paths.get(project.buildscript.sourceFile.parent, project.cargokit.manifestDir)",
        "def manifestDir = Paths.get(project.buildscript.sourceFile.parent, project.cargokit.manifestDir).toString()",
    )
    text = text.replace(
        "def rootProjectDir = project.rootProject.projectDir",
        "def rootProjectDir = project.rootProject.projectDir.toString()",
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    hosted_root = pub_cache() / "hosted"
    if not hosted_root.exists():
        print(f"Pub cache not found: {pub_cache()}")
        return 1

    changed = 0
    found = 0
    for hosted in [p for p in hosted_root.iterdir() if p.is_dir()]:
        for name in ("irondash_engine_context", "super_native_extensions"):
            package = find_package(hosted, name)
            if package is None:
                continue
            found += 1
            plugin = package / "cargokit" / "gradle" / "plugin.gradle"
            if patch(plugin):
                changed += 1
                print(f"[patched] {plugin}")
            else:
                print(f"[ok] already compatible: {plugin}")

    if found == 0:
        print("No CargoKit packages found. Run `flutter pub get` first.")
        return 1
    print(f"Done. {found} package(s) checked, {changed} changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
