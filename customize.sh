#!/system/bin/sh
SKIPUNZIP=0

ui_print "********************************************"
ui_print " Qualcomm Legacy eUICC Fix v1.0.0"
ui_print " Target: EasyEUICC / OpenEUICC (v1.7.2)"
ui_print " Bypass: 6-byte partial ISD-R AID A00000055910"
ui_print "********************************************"

if pm list features 2>/dev/null | grep -Fq "android.hardware.se.omapi.uicc" \
   || [ -f /vendor/etc/permissions/android.hardware.se.omapi.uicc.xml ] \
   || [ -f /odm/etc/permissions/android.hardware.se.omapi.uicc.xml ]; then
    ui_print "- System already declares android.hardware.se.omapi.uicc (overlay stays safe)"
else
    ui_print "- Adding systemless android.hardware.se.omapi.uicc permission XML"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/common/patch_euicc_prefs.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Checking installed EasyEUICC / OpenEUICC apps..."
sh "$MODPATH/common/patch_euicc_prefs.sh" "$MODPATH" | while IFS= read -r line; do
    ui_print "  $line"
done

ui_print "- Done! Reboot to activate OMAPI UICC overlay."
