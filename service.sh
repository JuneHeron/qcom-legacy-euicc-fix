#!/system/bin/sh
MODDIR="${0%/*}"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do
    sleep 1
    i=$((i + 1))
done

sleep 3
sh "$MODDIR/common/patch_euicc_prefs.sh" "$MODDIR" > "$MODDIR/service.log" 2>&1
