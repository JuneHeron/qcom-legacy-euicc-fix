#!/usr/bin/env python3
"""Audit & verification harness for qcom-legacy-euicc-fix."""

import argparse
import base64
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

EXPECTED_AIDS = [
    "A00000055910",
    "A0000005591010FFFFFFFF8900000100",
    "A0000005591010000000008900000300",
    "A0000005591010FFFFFFFF8900050500",
    "A0000005591010FFFFFFFF8900000177",
    "A000000559104C696E6B736669656C64",
    "A06573746B6D65FFFF4953442D522030",
    "A06573746B6D65FFFF4953442D522031",
    "A06573746B6D65FFFFFFFF4953442D52",
]

MODULE_TEXT_FILES = [
    "module.prop",
    "customize.sh",
    "service.sh",
    "action.sh",
    "uninstall.sh",
    "common/patch_euicc_prefs.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "system/etc/permissions/android.hardware.se.omapi.uicc.xml",
]

EXPECTED_ZIP_ENTRIES = set(MODULE_TEXT_FILES)


def _read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    val = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7


def _encode_varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _pb_field_bytes(field_num: int, wire_type: int, payload: bytes) -> bytes:
    return _encode_varint((field_num << 3) | wire_type) + _encode_varint(len(payload)) + payload


def _decode_value(raw: bytes):
    pos = 0
    while pos < len(raw):
        tag, pos = _read_varint(raw, pos)
        field_num = tag >> 3
        wire_type = tag & 0x7
        if wire_type == 0:
            v, pos = _read_varint(raw, pos)
            if field_num == 1:
                return bool(v)
            return v
        elif wire_type == 2:
            ln, pos = _read_varint(raw, pos)
            val = raw[pos : pos + ln]
            pos += ln
            if field_num == 5:
                return val.decode("utf-8")
            return val
        elif wire_type == 5:
            pos += 4
        elif wire_type == 1:
            pos += 8
        else:
            raise ValueError(f"Unsupported wire_type {wire_type}")
    return None


def _decode_entry(raw: bytes) -> tuple[str, object]:
    pos = 0
    key = None
    val = None
    while pos < len(raw):
        tag, pos = _read_varint(raw, pos)
        field_num = tag >> 3
        wire_type = tag & 0x7
        if wire_type != 2:
            raise ValueError(f"Unexpected wire_type {wire_type} in MapEntry")
        ln, pos = _read_varint(raw, pos)
        payload = raw[pos : pos + ln]
        pos += ln
        if field_num == 1:
            key = payload.decode("utf-8")
        elif field_num == 2:
            val = _decode_value(payload)
    if key is None:
        raise ValueError("MapEntry missing key")
    return key, val


def decode_preferences_pb(raw: bytes) -> dict:
    """Decode a Jetpack DataStore PreferencesProto binary blob into a dict."""
    result = {}
    pos = 0
    while pos < len(raw):
        tag, pos = _read_varint(raw, pos)
        field_num = tag >> 3
        wire_type = tag & 0x7
        if field_num != 1 or wire_type != 2:
            raise ValueError(f"Unexpected top-level field {field_num} wire_type {wire_type}")
        ln, pos = _read_varint(raw, pos)
        entry_raw = raw[pos : pos + ln]
        pos += ln
        k, v = _decode_entry(entry_raw)
        result[k] = v
    return result


def extract_payload_from_script(path: Path) -> tuple[str, bytes]:
    text = path.read_text(encoding="utf-8")
    m_marker = re.search(r'^MARKER_B64="([^"]+)"', text, re.MULTILINE)
    m_pb = re.search(r'^ISDR_PB_B64="([^"]+)"', text, re.MULTILINE)
    if not m_marker or not m_pb:
        raise AssertionError("Missing MARKER_B64 or ISDR_PB_B64 in patch_euicc_prefs.sh")
    return m_marker.group(1), base64.b64decode(m_pb.group(1), validate=True)


def check_lf_only(rel_paths: list[str]) -> None:
    for rel in rel_paths:
        p = ROOT / rel
        assert p.is_file(), f"Missing required file: {rel}"
        raw = p.read_bytes()
        assert b"\r" not in raw, f"CRLF detected in {rel}; must be LF only"


def build_sample_bool_prefs() -> bytes:
    def make_bool_entry(k: str, bval: bool) -> bytes:
        vmsg = _encode_varint((1 << 3) | 0) + _encode_varint(1 if bval else 0)
        ent = _pb_field_bytes(1, 2, k.encode("utf-8")) + _pb_field_bytes(2, 2, vmsg)
        return _pb_field_bytes(1, 2, ent)

    return make_bool_entry("skip_quick_compatibility", True) + make_bool_entry("verbose_logging", True)


def build_sample_old_isdr_prefs() -> bytes:
    old_aids = "\n".join(EXPECTED_AIDS[1:]).encode("utf-8")
    vmsg = _pb_field_bytes(5, 2, base64.b64encode(old_aids))
    ent = _pb_field_bytes(1, 2, b"isdr_aid_list") + _pb_field_bytes(2, 2, vmsg)
    return _pb_field_bytes(1, 2, ent)


def check_zip(zip_path: Path) -> None:
    assert zip_path.is_file(), f"ZIP not found: {zip_path}"
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = set(zf.namelist())
        assert names == EXPECTED_ZIP_ENTRIES, (
            f"ZIP entries mismatch!\n  extra={names - EXPECTED_ZIP_ENTRIES}\n  missing={EXPECTED_ZIP_ENTRIES - names}"
        )
        for name in names:
            data = zf.read(name)
            assert b"\r" not in data, f"CRLF detected inside ZIP entry {name}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-zip", type=Path, default=None, help="Verify built flashable ZIP")
    args = parser.parse_args()

    script_path = ROOT / "common" / "patch_euicc_prefs.sh"
    if not script_path.is_file():
        raise FileNotFoundError(f"Missing {script_path}")

    marker_b64, payload = extract_payload_from_script(script_path)
    expected_marker = base64.b64encode(b"A00000055910").decode("ascii")
    assert marker_b64 == expected_marker, f"MARKER_B64 {marker_b64} != {expected_marker}"
    assert len(payload) == 392, f"Expected payload len 392, got {len(payload)}"

    decoded = decode_preferences_pb(payload)
    assert list(decoded.keys()) == ["isdr_aid_list"], f"Unexpected keys: {decoded.keys()}"
    aids_text = base64.b64decode(decoded["isdr_aid_list"], validate=True).decode("utf-8")
    assert aids_text.splitlines() == EXPECTED_AIDS, f"AID list mismatch: {aids_text!r}"

    # Test merge onto: (a) empty file, (b) bools fixture, (c) older isdr_aid_list fixture
    for label, base_blob, expected_extra in [
        ("empty", b"", {}),
        ("booleans", build_sample_bool_prefs(), {"skip_quick_compatibility": True, "verbose_logging": True}),
        ("old_isdr", build_sample_old_isdr_prefs(), {}),
    ]:
        merged = decode_preferences_pb(base_blob + payload)
        for k, v in expected_extra.items():
            assert merged.get(k) == v, f"[{label}] Lost existing key {k}: {merged}"
        merged_aids = base64.b64decode(merged["isdr_aid_list"], validate=True).decode("utf-8").splitlines()
        assert merged_aids == EXPECTED_AIDS, f"[{label}] Merged AIDs mismatch: {merged_aids}"

    check_lf_only(MODULE_TEXT_FILES)

    if args.check_zip is not None:
        check_zip(args.check_zip)

    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
