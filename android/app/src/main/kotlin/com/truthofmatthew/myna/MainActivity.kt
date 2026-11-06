package com.truthofmatthew.myna

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Pairing (from the QR link), permissions, and connect / disconnect. */
class MainActivity : Activity() {
    private lateinit var title: TextView
    private lateinit var status: TextView
    private lateinit var connect: Button
    private lateinit var forget: Button
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() { render(); handler.postDelayed(this, 1000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (24 * resources.displayMetrics.density).toInt()
        title = TextView(this).apply { textSize = 22f }
        status = TextView(this).apply { textSize = 16f; setPadding(0, pad / 2, 0, pad) }
        connect = Button(this).apply { setOnClickListener { toggle() } }
        forget = Button(this).apply {
            text = "Forget this Mac"
            setOnClickListener { LinkService.stop(this@MainActivity); Pairing.forget(this@MainActivity); render() }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(pad, pad, pad, pad)
            addView(title); addView(status); addView(connect); addView(forget)
        })
        handlePairing(intent)
        // Opening Myna means you want it connected; no need to tap Connect every time.
        if (intent?.data == null && savedInstanceState == null && Pairing.load(this) != null && LinkService.status == "Stopped") start()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePairing(intent)
    }

    override fun onResume() { super.onResume(); handler.post(refresh) }
    override fun onPause() { super.onPause(); handler.removeCallbacks(refresh) }

    private fun handlePairing(intent: Intent?) {
        val uri = intent?.data ?: return
        val pairing = Pairing.parse(uri)
        if (pairing == null) { status.text = "That pairing code didn't work. Show a new one on your Mac."; return }
        LinkService.stop(this)
        pairing.save(this)
        start()
    }

    private fun toggle() {
        if (LinkService.status == "Stopped" || LinkService.status == "Not paired") start() else LinkService.stop(this)
        handler.postDelayed({ render() }, 300)
    }

    private fun start() {
        val missing = (REQUIRED + OPTIONAL).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) LinkService.start(this) else requestPermissions(missing.toTypedArray(), 1)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        // Texts are optional: without SMS access the camera and mic still work.
        if (REQUIRED.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) LinkService.start(this)
        else status.text = "Myna needs the camera, microphone and local network to work as your Mac's webcam."
    }

    private fun render() {
        val pairing = Pairing.load(this)
        if (pairing == null) {
            title.text = "Pair with your Mac"
            status.text = "On your Mac, open Myna from the menu bar and choose Pair Phone. Then scan the code with this phone's camera."
            connect.visibility = android.view.View.GONE
            forget.visibility = android.view.View.GONE
            return
        }
        val stopped = LinkService.status == "Stopped"
        title.text = pairing.name
        status.text = LinkService.status
        connect.visibility = android.view.View.VISIBLE
        connect.text = if (stopped) "Connect" else "Disconnect"
        forget.visibility = android.view.View.VISIBLE
    }

    companion object {
        private val REQUIRED = listOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.POST_NOTIFICATIONS,
            "android.permission.ACCESS_LOCAL_NETWORK",
        )
        private val OPTIONAL = listOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_CONTACTS,
        )
    }
}
