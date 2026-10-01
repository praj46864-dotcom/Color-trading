package com.example.agent

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var log: TextView
    private lateinit var key: EditText
    private lateinit var question: EditText
    private lateinit var secs: EditText

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val prefs = getSharedPreferences("p", MODE_PRIVATE)
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2)
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
        }
        key = EditText(this).apply {
            hint = "Anthropic API key"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setText(prefs.getString("key", ""))
        }
        question = EditText(this).apply {
            hint = "Screen ke baare me kya poochna hai"
            setText(prefs.getString("q", "Is screen par kya hai aur mujhe aage kya karna chahiye?"))
        }
        secs = EditText(this).apply {
            hint = "Session seconds"
            inputType = InputType.TYPE_CLASS_NUMBER
            setText(prefs.getString("secs", "60"))
        }
        val share = Button(this).apply { text = "Share & Analyze" }
        val stop = Button(this).apply { text = "STOP" }
        log = TextView(this)

        share.setOnClickListener {
            if (key.text.isBlank() || question.text.isBlank()) {
                log.append("API key aur sawal dono bharo.\n")
                return@setOnClickListener
            }
            prefs.edit().putString("key", key.text.toString().trim())
                .putString("q", question.text.toString().trim())
                .putString("secs", secs.text.toString().trim()).apply()
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), 1)
        }
        stop.setOnClickListener {
            startService(Intent(this, ShareService::class.java).setAction("STOP"))
        }

        ShareService.onLog = { line -> runOnUiThread { log.append(line + "\n\n") } }

        listOf(key, question, secs, share, stop).forEach { root.addView(it) }
        root.addView(ScrollView(this).apply { addView(log) })
        setContentView(root)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        if (req == 1 && res == RESULT_OK && data != null) {
            startForegroundService(
                Intent(this, ShareService::class.java)
                    .putExtra("code", res)
                    .putExtra("data", data)
                    .putExtra("key", key.text.toString().trim())
                    .putExtra("q", question.text.toString().trim())
                    .putExtra("secs", secs.text.toString().toLongOrNull() ?: 60L)
            )
        } else if (req == 1) {
            log.append("Screen share allow nahi hua.\n")
        }
    }

    override fun onDestroy() {
        ShareService.onLog = null
        super.onDestroy()
    }
}
