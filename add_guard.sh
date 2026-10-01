#!/bin/bash
# Banking aur government apps par analysis block. Baaki sab jagah chalega.
# Pehle add_share.sh chal chuka hona chahiye.
# Usage: repo ke root me:  bash add_guard.sh
set -e
P=app/src/main/java/com/example/agent

cat > $P/Guard.kt <<'EOF'
package com.example.agent

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process

// Foreground app ka package dekhta hai. Banking/payment/government jaisa lage to analysis roka jaata hai.
// Is app ka screenshot API ko bheja hi nahi jaata jab tak aisa app khula ho.
object Guard {

    // Package ke naam me ye shabd kahin bhi ho to block
    private val contains = listOf(
        "bank", "hdfc", "icici", "kotak", "paytm", "phonepe", "paisa", "bhim", "wallet",
        "payment", "canara", "idfc", "yesbank", "indusind", "bandhan", "digilocker",
        "aadhaar", "uidai", "umang", "incometax", "irctc", "mparivahan", "cowin",
        "aarogya", "epfo", "mygov", "nsdl", "cred.club"
    )

    // Package ke "." se bane hisse (segment) ye ho to block
    private val segments = setOf("gov", "nic", "axis", "sbi", "pnb")

    fun hasUsageAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun foregroundPackage(ctx: Context): String? {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val ev = usm.queryEvents(now - 6 * 3600_000L, now)
        val e = UsageEvents.Event()
        var last: String? = null
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.ACTIVITY_RESUMED) last = e.packageName
        }
        return last
    }

    // Blocked app ka package wapas deta hai, warna null
    fun blockedApp(ctx: Context): String? {
        val pkg = foregroundPackage(ctx) ?: return null
        val p = pkg.lowercase()
        val segs = p.split(".")
        return if (contains.any { p.contains(it) } || segs.any { it in segments }) pkg else null
    }
}
EOF

python3 - <<'PY'
import sys

def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if new in s:
        return
    if old not in s:
        sys.exit("Patch fail: " + path)
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))

base = "app/src/main/java/com/example/agent/"

patch("app/src/main/AndroidManifest.xml",
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.INTERNET" />\n'
    '    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" />')

patch(base + "MainActivity.kt",
    'val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager',
    'if (!Guard.hasUsageAccess(this)) {\n'
    '                log.append("Usage access me Screen Agent ON karo, phir wapas aakar Share & Analyze dabao.\\n")\n'
    '                startActivity(Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS))\n'
    '                return@setOnClickListener\n'
    '            }\n'
    '            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager')

patch(base + "ShareService.kt",
    'Hinglish me likho, 8 line se kam.',
    'Hinglish me likho, 8 line se kam.\n'
    'Agar screen kisi banking, UPI/payment ya sarkari (government) app ya website ki ho, to jawab me sirf ek shabd likho: BLOCKED')

patch(base + "ShareService.kt",
    'val ans = ask(key, q, jpeg)',
    'val blocked = Guard.blockedApp(this)\n'
    '                if (blocked != null) {\n'
    '                    log("Sensitive app ($blocked) khula hai - analysis pause")\n'
    '                    Thread.sleep(3000)\n'
    '                    continue\n'
    '                }\n'
    '                val ans = ask(key, q, jpeg)\n'
    '                if (ans.trim().startsWith("BLOCKED")) { reason = "Banking/government screen mili - session roka gaya"; break }')

print("Guard patch lag gaya.")
PY

echo "Done. Ab: git add . && git commit -m guard && git push"
