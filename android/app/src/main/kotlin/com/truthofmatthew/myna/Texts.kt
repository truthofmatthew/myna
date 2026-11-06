package com.truthofmatthew.myna

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Handler
import android.os.HandlerThread
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
            "sms.sync" -> sync(message.optInt("limit"))
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

    /**
     * The newest [limit] texts (0 for all of them), newest first, in pages: the first replaces the Mac's list so it
     * fills fast, the rest add to it. Each page carries the total for the Mac's progress bar; the last says done.
     */
    private fun sync(limit: Int) {
        var page = ArrayList<JSONObject>()
        var sent = 0
        var total = 0
        fun flush(done: Boolean) {
            send(JSONObject().put("t", if (sent == 0) "sms.list" else "sms.more").put("messages", JSONArray(page))
                .put("total", total).put("done", done))
            sent += page.size
            page = ArrayList()
        }
        walk("1=1", emptyArray(), { total = if (limit > 0) minOf(limit, it) else it }) {
            page += it
            val last = sent + page.size == total
            if (page.size == PAGE || last) flush(last)
            !last
        }
        if (sent == 0 || page.isNotEmpty()) flush(true)
    }

    /** Newest first. */
    private fun query(selection: String, args: Array<String>, limit: Int): List<JSONObject> {
        val out = ArrayList<JSONObject>()
        walk(selection, args) { out += it; out.size < limit }
        return out
    }

    /** Tells [count] how many rows matched, then hands each text to [each], newest first, until it returns false. */
    private fun walk(selection: String, args: Array<String>, count: (Int) -> Unit = {}, each: (JSONObject) -> Boolean) {
        val columns = arrayOf("_id", "thread_id", "address", "body", "date", "type", "read")
        resolver.query(Telephony.Sms.CONTENT_URI, columns, selection, args, "date DESC")?.use { c ->
            count(c.count)
            while (c.moveToNext()) {
                val address = c.getString(2) ?: continue
                val text = JSONObject()
                    .put("id", c.getLong(0)).put("thread", c.getLong(1)).put("address", address)
                    .put("body", c.getString(3) ?: "").put("date", c.getLong(4)).put("type", c.getInt(5))
                    .put("read", c.getInt(6) == 1)
                    .apply { name(address)?.let { put("name", it) } }
                if (!each(text)) break
            }
        }
    }

    private fun name(address: String): String? = names.getOrPut(address) { contactName(context, address) }

    companion object {
        private const val ACTION_SENT = "com.truthofmatthew.myna.SMS_SENT"
        // About 1 MB of JSON at most, well under the 4 MB frame limit.
        private const val PAGE = 1000
    }
}
