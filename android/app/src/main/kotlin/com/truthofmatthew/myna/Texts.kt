package com.truthofmatthew.myna

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

/**
 * Text messages for the Mac: reads the phone's SMS store, watches it for new messages, and sends texts.
 * Samsung Messages (the default SMS app) writes every text to that store, received or sent.
 */
class Texts(private val context: Context, private val send: (JSONObject) -> Unit) {
    private val resolver = context.contentResolver
    private val thread = HandlerThread("myna-texts").apply { start() }
    private val handler = Handler(thread.looper)
    private val names = HashMap<String, String?>()
    private var lastId = 0L
    private val nextRequest = AtomicInteger(1)

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) = pushNew()
    }

    private val sentReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            send(JSONObject().put("t", "sms.sent").put("ref", intent.getStringExtra("ref")).put("ok", resultCode == android.app.Activity.RESULT_OK))
        }
    }

    private val allowed get() = context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    fun start() = handler.post {
        if (!allowed) return@post
        lastId = query("1=1", emptyArray(), 1).firstOrNull()?.getLong("id") ?: 0L
        resolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
        context.registerReceiver(sentReceiver, IntentFilter(ACTION_SENT), Context.RECEIVER_NOT_EXPORTED)
    }

    fun stop() {
        handler.post {
            runCatching { resolver.unregisterContentObserver(observer) }
            runCatching { context.unregisterReceiver(sentReceiver) }
            thread.quitSafely()
        }
    }

    fun handle(message: JSONObject) = handler.post {
        if (!allowed) return@post send(JSONObject().put("t", "sms.error").put("error", "Allow Myna to read and send SMS on the phone."))
        when (message.optString("t")) {
            "sms.sync" -> send(JSONObject().put("t", "sms.list").put("messages", JSONArray(query("1=1", emptyArray(), SYNC_LIMIT))))
            "sms.send" -> sendText(message.optString("to"), message.optString("body"), message.optString("ref"))
            "sms.read" -> {
                // Prefer Samsung's own "Mark as read" button; otherwise the Mac adds it to a batch.
                val done = Notifications.active?.markRead(message.optString("address"), message.optString("name").ifEmpty { null }) == true
                send(JSONObject().put("t", "sms.read.done").put("ids", message.optJSONArray("ids")).put("ok", done))
            }
            "sms.batch" -> {
                Batch.save(context, message.toString())
                Batch.notify(context, BatchActivity.summary(message))
            }
        }
    }

    private fun pushNew() {
        val fresh = query("_id > ?", arrayOf(lastId.toString()), 200)
        if (fresh.isEmpty()) return
        lastId = fresh.maxOf { it.getLong("id") }
        send(JSONObject().put("t", "sms.new").put("messages", JSONArray(fresh)))
    }

    private fun sendText(to: String, body: String, ref: String) {
        if (to.isBlank() || body.isEmpty() || context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            return send(JSONObject().put("t", "sms.sent").put("ref", ref).put("ok", false))
        }
        val sms = context.getSystemService(SmsManager::class.java)
        val parts = sms.divideMessage(body)
        // Only the last part reports back; the text counts as sent once all of it went out.
        val done = PendingIntent.getBroadcast(context, nextRequest.getAndIncrement(),
            Intent(ACTION_SENT).setPackage(context.packageName).putExtra("ref", ref), PendingIntent.FLAG_IMMUTABLE)
        val sent = ArrayList<PendingIntent?>(parts.map { null }).apply { set(size - 1, done) }
        sms.sendMultipartTextMessage(to, null, parts, sent, null)
    }

    /** Newest first. */
    private fun query(selection: String, args: Array<String>, limit: Int): List<JSONObject> {
        val out = ArrayList<JSONObject>()
        val columns = arrayOf("_id", "thread_id", "address", "body", "date", "type", "read")
        resolver.query(Telephony.Sms.CONTENT_URI, columns, selection, args, "date DESC")?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                val address = c.getString(2) ?: continue
                out += JSONObject()
                    .put("id", c.getLong(0)).put("thread", c.getLong(1)).put("address", address)
                    .put("body", c.getString(3) ?: "").put("date", c.getLong(4)).put("type", c.getInt(5))
                    .put("read", c.getInt(6) == 1)
                    .apply { name(address)?.let { put("name", it) } }
            }
        }
        return out
    }

    private fun name(address: String): String? = names.getOrPut(address) {
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
        resolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }

    companion object {
        private const val ACTION_SENT = "com.truthofmatthew.myna.SMS_SENT"
        private const val SYNC_LIMIT = 2000
    }
}
