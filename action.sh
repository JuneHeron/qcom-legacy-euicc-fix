#!/system/bin/sh
MODDIR="${0%/*}"

echo "============================================"
echo " Qualcomm Legacy eUICC Fix (A00000055910)"
echo " Verified target: EasyEUICC / OpenEUICC v1.7.2"
echo "============================================"

sh "$MODDIR/common/patch_euicc_prefs.sh" "$MODDIR"
rc=$?

echo "--------------------------------------------"
if [ "$rc" -eq 0 ]; then
    echo "Done. Reopen EasyEUICC / OpenEUICC to verify."
else
    echo "Finished with errors (exit=$rc)."
fi
exit "$rc"
