#!/usr/bin/env python3
"""Reproducible flashable ZIP builder for qcom-legacy-euicc-fix."""

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import verify_payload  # noqa: E402

ARCHIVE_FILES = [
    ("META-INF/com/google/android/update-binary", 0o755),
    ("META-INF/com/google/android/updater-script", 0o644),
    ("module.prop", 0o644),
    ("customize.sh", 0o644),
    ("service.sh", 0o755),
    ("action.sh", 0o755),
    ("uninstall.sh", 0o755),
    ("common/patch_euicc_prefs.sh", 0o755),
    ("system/etc/permissions/android.hardware.se.omapi.uicc.xml", 0o644),
]


def read_module_version() -> str:
    for line in (ROOT / "module.prop").read_text(encoding="utf-8").splitlines():
        if line.startswith("version="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError("version= not found in module.prop")


def main() -> int:
    # Run full payload & LF checks before packaging
    assert verify_payload.main() == 0

    version = read_module_version()
    dist_dir = ROOT / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    out_zip = dist_dir / f"qcom-legacy-euicc-fix-{version}.zip"

    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel, mode in ARCHIVE_FILES:
            src = ROOT / rel
            data = src.read_bytes()
            assert b"\r" not in data, f"Refusing to archive CRLF file: {rel}"
            zi = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))
            zi.create_system = 3  # Unix
            zi.external_attr = (0o100000 | mode) << 16
            zf.writestr(zi, data)

    verify_payload.check_zip(out_zip)
    print(f"Built verified archive: {out_zip} ({out_zip.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
