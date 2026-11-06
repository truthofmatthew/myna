package com.truthofmatthew.myna

import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.util.Log

/**
 * A non-UI in-call service: on Android 17 only services in the call may change a cell call's audio route.
 * Telecom binds it during calls when Myna holds MANAGE_ONGOING_CALLS (the permission watch apps get).
 */
class InCall : InCallService() {
    override fun onCallAdded(call: Call) { active = this; Log.i(TAG, "in call") }
    override fun onCallRemoved(call: Call) { if (calls.isEmpty() && active === this) active = null }

    @Suppress("DEPRECATION") // setAudioRoute: replaced by requestCallEndpointChange, which needs the endpoint list first
    fun speaker() = setAudioRoute(CallAudioState.ROUTE_SPEAKER)

    companion object {
        private const val TAG = "MynaInCall"
        @Volatile var active: InCall? = null
    }
}
