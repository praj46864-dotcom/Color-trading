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
