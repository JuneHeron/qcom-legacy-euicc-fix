#!/system/bin/sh
# Pure-shell Jetpack DataStore patcher for EasyEUICC / OpenEUICC (verified on v1.7.2).
# Appends a standard PreferencesProto MapEntry for key "isdr_aid_list" containing
# the 6-byte ISO 7816-4 partial ISD-R AID "A00000055910" ahead of the 8 default AIDs:
#   A00000055910
#   A0000005591010FFFFFFFF8900000100
#   A0000005591010000000008900000300
#   A0000005591010FFFFFFFF8900050500
#   A0000005591010FFFFFFFF8900000177
#   A000000559104C696E6B736669656C64
#   A06573746B6D65FFFF4953442D522030
#   A06573746B6D65FFFF4953442D522031
#   A06573746B6D65FFFFFFFF4953442D52
# Verify byte-for-byte with: python tools/verify_payload.py

MODDIR="${1:-$(CDPATH= cd -- "${0%/*}/.." && pwd)}"
TARGET_PKGS="im.angry.easyeuicc im.angry.openeuicc"

# Base64("A00000055910") -> used for idempotent detection inside prefs.preferences_pb
MARKER_B64="QTAwMDAwMDU1OTEw"

# Pre-encoded 392-byte PreferencesProto MapEntry for "isdr_aid_list"
ISDR_PB_B64="CoUDCg1pc2RyX2FpZF9saXN0EvMCKvACUVRBd01EQXdNRFUxT1RFd0NrRXdNREF3TURBMU5Ua3hNREV3UmtaR1JrWkdSa1k0T1RBd01EQXdNVEF3Q2tFd01EQXdNREExTlRreE1ERXdNREF3TURBd01EQTRPVEF3TURBd016QXdDa0V3TURBd01EQTFOVGt4TURFd1JrWkdSa1pHUmtZNE9UQXdNRFV3TlRBd0NrRXdNREF3TURBMU5Ua3hNREV3UmtaR1JrWkdSa1k0T1RBd01EQXdNVGMzQ2tFd01EQXdNREExTlRreE1EUkROamsyUlRaQ056TTJOalk1TmpVMlF6WTBDa0V3TmpVM016YzBOa0kyUkRZMVJrWkdSalE1TlRNME5ESkVOVEl5TURNd0NrRXdOalUzTXpjME5rSTJSRFkxUmtaR1JqUTVOVE0wTkRKRU5USXlNRE14Q2tFd05qVTNNemMwTmtJMlJEWTFSa1pHUmtaR1JrWTBPVFV6TkRReVJEVXk="

BACKUP_DIR="$MODDIR/backups"
mkdir -p "$BACKUP_DIR" 2>/dev/null
TMP_PAYLOAD="$BACKUP_DIR/.payload.pb"

cleanup() {
    rm -f "$TMP_PAYLOAD" 2>/dev/null
}
trap cleanup EXIT HUP INT TERM

decode_payload_to() {
    out="$1"
    rm -f "$out" 2>/dev/null

    for cmd in \
        "base64 -d" \
        "toybox base64 -d" \
        "/data/adb/magisk/busybox base64 -d" \
        "/data/adb/ksu/bin/busybox base64 -d" \
        "/data/adb/ap/bin/busybox base64 -d"
    do
        bin="${cmd%% *}"
        if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
            printf '%s' "$ISDR_PB_B64" | $cmd > "$out" 2>/dev/null
            if [ -s "$out" ]; then
                return 0
            fi
            rm -f "$out" 2>/dev/null
        fi
    done

    return 1
}

if ! decode_payload_to "$TMP_PAYLOAD"; then
    echo "[err] Failed to decode payload: no working base64 decoder found"
    exit 1
fi

found_count=0
err_count=0

for pkg in $TARGET_PKGS; do
    DATA_DIR="/data/user/0/$pkg"
    [ -d "$DATA_DIR" ] || continue
    found_count=$((found_count + 1))

    FILES_DIR="$DATA_DIR/files"
    DS_DIR="$FILES_DIR/datastore"
    PREFS_FILE="$DS_DIR/prefs.preferences_pb"

    if [ -f "$PREFS_FILE" ] && grep -Fq "$MARKER_B64" "$PREFS_FILE" 2>/dev/null; then
        echo "[skip] $pkg already contains A00000055910"
        continue
    fi

    OWNER="$(stat -c '%u:%g' "$DATA_DIR" 2>/dev/null)"
    if [ -z "$OWNER" ]; then
        echo "[err] Cannot determine uid:gid for $pkg"
        err_count=$((err_count + 1))
        continue
    fi

    am force-stop "$pkg" >/dev/null 2>&1 || true

    if [ -f "$PREFS_FILE" ] && [ ! -f "$BACKUP_DIR/$pkg.preferences_pb.bak" ]; then
        cp -f "$PREFS_FILE" "$BACKUP_DIR/$pkg.preferences_pb.bak"
    fi

    files_existed=1
    [ -d "$FILES_DIR" ] || files_existed=0
    mkdir -p "$DS_DIR" || {
        echo "[err] Failed to create $DS_DIR"
        err_count=$((err_count + 1))
        continue
    }

    TMP_OUT="$BACKUP_DIR/.tmp.$pkg.pb"
    rm -f "$TMP_OUT" 2>/dev/null

    if [ -f "$PREFS_FILE" ]; then
        cat "$PREFS_FILE" "$TMP_PAYLOAD" > "$TMP_OUT"
    else
        cp -f "$TMP_PAYLOAD" "$TMP_OUT"
    fi

    if [ ! -s "$TMP_OUT" ]; then
        rm -f "$TMP_OUT" 2>/dev/null
        echo "[err] Refusing to write empty DataStore file for $pkg"
        err_count=$((err_count + 1))
        continue
    fi

    mv -f "$TMP_OUT" "$PREFS_FILE" || {
        rm -f "$TMP_OUT" 2>/dev/null
        echo "[err] Failed to move patched file into $PREFS_FILE"
        err_count=$((err_count + 1))
        continue
    }

    if [ "$files_existed" -eq 0 ]; then
        chown "$OWNER" "$FILES_DIR"
        chmod 700 "$FILES_DIR"
        restorecon "$FILES_DIR" >/dev/null 2>&1 || chcon --reference="$DATA_DIR" "$FILES_DIR" >/dev/null 2>&1 || true
    fi

    chown "$OWNER" "$DS_DIR" "$PREFS_FILE"
    chmod 700 "$DS_DIR"
    chmod 600 "$PREFS_FILE"
    restorecon "$DS_DIR" "$PREFS_FILE" >/dev/null 2>&1 || chcon --reference="$DATA_DIR" "$DS_DIR" "$PREFS_FILE" >/dev/null 2>&1 || true

    echo "[ok] $pkg configured with partial ISD-R AID A00000055910"
done

if [ "$found_count" -eq 0 ]; then
    echo "[info] Neither EasyEUICC nor OpenEUICC is installed yet."
    echo "[info] Install EasyEUICC (v1.7.2) then tap Action or reboot to auto-configure."
fi

[ "$err_count" -eq 0 ]
