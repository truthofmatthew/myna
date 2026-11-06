package com.truthofmatthew.myna

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log

// Android only offers the SMS role to an app that can receive SMS and MMS, send from a share sheet and answer
// "respond via message". Myna holds the role for a minute while it deletes or blocks for the Mac
// (BatchActivity), so these do just enough that nothing is lost in that minute.

/** While Myna is the SMS app, incoming texts come here instead of Samsung Messages; store them like it would. */
class SmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val first = parts.firstOrNull() ?: return
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, first.displayOriginatingAddress)
            put(Telephony.Sms.BODY, parts.joinToString("") { it.displayMessageBody ?: "" })
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.DATE_SENT, first.timestampMillis)
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.SEEN, 0)
            put(Telephony.Sms.SUBSCRIPTION_ID, intent.getIntExtra("subscription", -1))
        }
        context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
        // Samsung Messages isn't the SMS app right now, so it won't show this one.
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("texts", "Texts while Myna is the SMS app", NotificationManager.IMPORTANCE_HIGH))
        manager.notify(first.displayOriginatingAddress.hashCode(), Notification.Builder(context, "texts")
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(first.displayOriginatingAddress)
            .setContentText(values.getAsString(Telephony.Sms.BODY))
            .setAutoCancel(true)
            .build())
    }
}

/** MMS that arrive in the minute Myna holds the role. shortcut: not downloaded; Samsung Messages fetches pending MMS when it's the SMS app again. */
class MmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { Log.i("MynaSms", "MMS arrived while Myna held the SMS role") }
}

/** "Respond via message" from the incoming-call screen. */
class RespondService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val to = intent?.data?.schemeSpecificPart?.substringBefore('?')
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)
        if (!to.isNullOrBlank() && !body.isNullOrBlank()) {
            val sms = getSystemService(SmsManager::class.java)
            sms.sendMultipartTextMessage(to, null, sms.divideMessage(body), null, null)
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}

/** Opened by "send text" links from other apps: hand them to whichever app normally writes texts. */
class ComposeActivity : android.app.Activity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val forward = Intent(intent).setComponent(null).setPackage(SAMSUNG_MESSAGES)
        startActivity(if (forward.resolveActivity(packageManager) != null) forward else Intent(this, MainActivity::class.java))
        finish()
    }
}

const val SAMSUNG_MESSAGES = "com.samsung.android.messaging"

/** The pending changes from the Mac, applied by BatchActivity once Myna holds the SMS role. */
object Batch {
    fun save(context: Context, json: String) = context.getSharedPreferences("batch", Context.MODE_PRIVATE).edit().putString("json", json).apply()
    fun load(context: Context): String? = context.getSharedPreferences("batch", Context.MODE_PRIVATE).getString("json", null)
    fun clear(context: Context) = context.getSharedPreferences("batch", Context.MODE_PRIVATE).edit().clear().apply()

    /** Asks the user on the phone to approve; the Mac can't switch the SMS app by itself. */
    fun notify(context: Context, summary: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("batch", "Changes from your Mac", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(context, 2, Intent(context, BatchActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(2, Notification.Builder(context, "batch")
            .setSmallIcon(android.R.drawable.ic_menu_delete)
            .setContentTitle("Your Mac wants to $summary")
            .setContentText("Tap to approve. Myna becomes the SMS app for a moment, then hands it back.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build())
    }
}
