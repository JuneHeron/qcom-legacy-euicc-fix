#!/system/bin/sh
MODDIR="${0%/*}"
BACKUP_DIR="$MODDIR/backups"

for pkg in im.angry.easyeuicc im.angry.openeuicc; do
    BAK="$BACKUP_DIR/$pkg.preferences_pb.bak"
    DATA_DIR="/data/user/0/$pkg"
    PREFS_FILE="$DATA_DIR/files/datastore/prefs.preferences_pb"

    if [ -f "$BAK" ] && [ -d "$DATA_DIR" ]; then
        OWNER="$(stat -c '%u:%g' "$DATA_DIR" 2>/dev/null)"
        if [ -n "$OWNER" ]; then
            am force-stop "$pkg" >/dev/null 2>&1 || true
            mkdir -p "$DATA_DIR/files/datastore"
            cp -f "$BAK" "$PREFS_FILE"
            chown "$OWNER" "$PREFS_FILE"
            chmod 600 "$PREFS_FILE"
            restorecon "$PREFS_FILE" >/dev/null 2>&1 || chcon --reference="$DATA_DIR" "$PREFS_FILE" >/dev/null 2>&1 || true
        fi
    fi
done
