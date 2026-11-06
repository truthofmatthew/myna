package com.truthofmatthew.myna

import android.app.Notification
import android.service.notification.NotificationListenerService

/**
 * Sees Samsung Messages' notifications so the Mac can mark a text read without Myna holding the SMS role:
 * it presses the notification's own "Mark as read" button. Needs Notification access, granted in Settings.
 */
class Notifications : NotificationListenerService() {
    override fun onListenerConnected() { active = this }
    override fun onListenerDisconnected() { if (active === this) active = null }

    /** True if a Samsung Messages notification for this sender had a mark-read action and it was pressed. */
    fun markRead(address: String, name: String?): Boolean {
        val digits = address.filter(Char::isDigit).takeLast(9)
        return activeNotifications.orEmpty()
            .filter { it.packageName == SAMSUNG_MESSAGES }
            .filter { sbn ->
                val title = sbn.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
                title == address || (name != null && title.contains(name)) ||
                    (digits.length >= 6 && title.filter(Char::isDigit).endsWith(digits))
            }
            .mapNotNull { sbn ->
                sbn.notification.actions?.firstOrNull { it.semanticAction == Notification.Action.SEMANTIC_ACTION_MARK_AS_READ }
                    ?: sbn.notification.actions?.firstOrNull { a -> a.title?.toString()?.let { it.contains("read", true) || it.contains("خوانده") } == true }
            }
            .onEach { runCatching { it.actionIntent.send() } }
            .isNotEmpty()
    }

    companion object {
        @Volatile var active: Notifications? = null
    }
}
