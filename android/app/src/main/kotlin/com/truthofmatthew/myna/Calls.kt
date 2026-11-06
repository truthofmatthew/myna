package com.truthofmatthew.myna

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import org.json.JSONObject

/**
 * Call control for the Mac: reports ringing, dialing, active and idle, and answers, hangs up or dials.
 * No audio: the call stays on the phone.
 */
class Calls(private val context: Context, private val send: (JSONObject) -> Unit) {
    private val thread = HandlerThread("myna-calls").apply { start() }
    private val telephony = context.getSystemService(TelephonyManager::class.java)
    private val telecom = context.getSystemService(TelecomManager::class.java)
    private val audio = context.getSystemService(AudioManager::class.java)
    private val handler = Handler(thread.looper)
    private var last = TelephonyManager.CALL_STATE_IDLE
    private var number: String? = null
    @Volatile private var speakerWanted = false // the Mac answered or dialed, so you're not holding the phone

    // PhoneStateListener is deprecated, but it's the one that still passes the caller's number (with READ_CALL_LOG).
    @Suppress("DEPRECATION")
    private val listener = object : PhoneStateListener({ r: Runnable -> Handler(thread.looper).post(r); Unit }) {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) = changed(state, phoneNumber)
    }

    private fun allowed(p: String) = context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    fun start() {
        if (allowed(Manifest.permission.READ_PHONE_STATE)) telephony.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    @Suppress("DEPRECATION")
    fun stop() {
        if (allowed(Manifest.permission.READ_PHONE_STATE)) telephony.listen(listener, PhoneStateListener.LISTEN_NONE)
        thread.quitSafely()
    }

    @SuppressLint("MissingPermission") // checked right before each call
    @Suppress("DEPRECATION") // endCall: deprecated for wearables' InCallService, still works for ANSWER_PHONE_CALLS holders
    fun handle(message: JSONObject) {
        when (message.optString("t")) {
            "call.answer" -> if (allowed(Manifest.permission.ANSWER_PHONE_CALLS)) {
                speakerWanted = message.optBoolean("speaker")
                telecom.acceptRingingCall()
            } else missing("answer calls")
            "call.end" -> if (allowed(Manifest.permission.ANSWER_PHONE_CALLS)) {
                if (!telecom.endCall()) error("The phone didn't hang up. Try on the phone.")
            } else missing("hang up")
            "call.dial" -> {
                val to = message.optString("number").filter { it.isDigit() || it == '+' || it == '*' || it == '#' }
                if (to.isEmpty()) return
                if (allowed(Manifest.permission.CALL_PHONE)) {
                    speakerWanted = message.optBoolean("speaker")
                    telecom.placeCall(Uri.fromParts("tel", to, null), null)
                } else missing("place calls")
            }
        }
    }

    private fun changed(state: Int, phoneNumber: String?) {
        if (!phoneNumber.isNullOrEmpty()) number = phoneNumber
        val name = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "ringing"
            // Off-hook straight from idle is a call you placed; from ringing, one you answered.
            TelephonyManager.CALL_STATE_OFFHOOK -> if (last == TelephonyManager.CALL_STATE_IDLE) "dialing" else "active"
            else -> "idle"
        }
        last = state
        // Telecom picks the earpiece when the call connects; switch after it has settled.
        if (state == TelephonyManager.CALL_STATE_OFFHOOK && speakerWanted) handler.postDelayed(::speakerOn, 800)
        if (state == TelephonyManager.CALL_STATE_IDLE && speakerWanted) { speakerWanted = false; audio.clearCommunicationDevice() }
        val m = JSONObject().put("t", "call.state").put("state", name)
        number?.let { n -> m.put("number", n); contactName(context, n)?.let { m.put("name", it) } }
        send(m)
        if (state == TelephonyManager.CALL_STATE_IDLE) number = null
    }

    @Suppress("DEPRECATION") // setSpeakerphoneOn: Telecom still follows it for cell calls on Samsung; the new API alone may not
    private fun speakerOn() {
        audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.let { audio.setCommunicationDevice(it) }
        audio.isSpeakerphoneOn = true
        send(JSONObject().put("t", "call.speaker").put("on", audio.communicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER || audio.isSpeakerphoneOn))
    }

    private fun missing(what: String) = error("Allow Myna to make and manage phone calls on the phone so the Mac can $what.")
    private fun error(text: String) = send(JSONObject().put("t", "call.error").put("error", text))
}

/** The contact's name for a number, if Myna may read contacts and one matches. */
fun contactName(context: Context, address: String): String? {
    if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
    val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
    return context.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { c ->
        if (c.moveToFirst()) c.getString(0) else null
    }
}
