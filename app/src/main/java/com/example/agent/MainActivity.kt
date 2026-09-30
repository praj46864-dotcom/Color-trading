package com.example.agent

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var log: TextView

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val prefs = getSharedPreferences("p", MODE_PRIVATE)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
        }
        val key = EditText(this).apply {
            hint = "Anthropic API key"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setText(prefs.getString("key", ""))
        }
        val task = EditText(this).apply {
            hint = "Kaam likho (kya karna hai)"
            setText(prefs.getString("task", ""))
        }
        val secs = EditText(this).apply {
            hint = "Session seconds"
            inputType = InputType.TYPE_CLASS_NUMBER
            setText(prefs.getString("secs", "120"))
        }
        val access = Button(this).apply {
            text = "1) Accessibility settings kholo"
            setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        }
        val start = Button(this).apply { text = "2) Start session" }
        val stop = Button(this).apply { text = "STOP" }
        log = TextView(this)

        start.setOnClickListener {
            val svc = AgentService.instance
            if (svc == null) {
                log.append("Pehle Accessibility me Screen Agent ON karo.\n")
                return@setOnClickListener
            }
            val k = key.text.toString().trim()
            val t = task.text.toString().trim()
            val s = secs.text.toString().toLongOrNull() ?: 120L
            if (k.isEmpty() || t.isEmpty()) {
                log.append("API key aur kaam dono bharo.\n")
                return@setOnClickListener
            }
            prefs.edit().putString("key", k).putString("task", t).putString("secs", s.toString()).apply()
            svc.startSession(k, t, s)
        }
        stop.setOnClickListener { AgentService.instance?.stopSession("Stop dabaya gaya") }

        AgentService.onLog = { line -> runOnUiThread { log.append(line + "\n") } }

        listOf(key, task, secs, access, start, stop).forEach { root.addView(it) }
        root.addView(ScrollView(this).apply { addView(log) })
        setContentView(root)
    }

    override fun onDestroy() {
        AgentService.onLog = null
        super.onDestroy()
    }
}
