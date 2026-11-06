package com.truthofmatthew.myna

import android.app.Activity
import android.app.role.RoleManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.os.Bundle
import android.provider.BlockedNumberContract.BlockedNumbers
import android.provider.Settings
import android.provider.Telephony
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject

/**
 * Applies the Mac's deletes, mark-reads, blocks and unblocks. Only the default SMS app may do these,
 * so Myna asks for the role, does the work, and then sends you back to Samsung Messages to take it back.
 */
class BatchActivity : Activity() {
    private lateinit var text: TextView
    private lateinit var button: Button
    private val roles by lazy { getSystemService(RoleManager::class.java) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (24 * resources.displayMetrics.density).toInt()
        text = TextView(this).apply { textSize = 18f; setPadding(0, 0, 0, pad) }
        button = Button(this)
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(pad, pad, pad, pad)
            addView(text); addView(button)
        })
        show()
    }

    override fun onResume() { super.onResume(); show() }

    private fun show() {
        val batch = Batch.load(this)?.let { JSONObject(it) }
        when {
            batch != null -> {
                text.text = "Your Mac wants to ${summary(batch)}.\n\nMyna becomes your SMS app for a moment to do it. Afterwards, pick Samsung Messages again in Default apps; Myna opens it for you."
                button.text = "Continue"
                button.setOnClickListener { apply() }
            }
            Telephony.Sms.getDefaultSmsPackage(this) == packageName -> {
                text.text = "Done. Now pick Samsung Messages as your SMS app again, or you'll miss picture messages."
                button.text = "Choose SMS App"
                button.setOnClickListener { handBack(this) }
            }
            else -> {
                text.text = "Nothing waiting from your Mac."
                button.text = "Close"
                button.setOnClickListener { finish() }
            }
        }
    }

    private fun apply() {
        if (!roles.isRoleHeld(RoleManager.ROLE_SMS)) {
            startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_SMS), 1)
            return
        }
        val batch = JSONObject(Batch.load(this) ?: return)
        button.isEnabled = false
        text.text = "Applying…"
        Thread {
            val result = run(batch)
            Batch.clear(this)
            LinkService.sendToMac(result)
            runOnUiThread { button.isEnabled = true; show(); handBack(this) }
        }.start()
    }

    @Deprecated("Activity result API needs AndroidX; this is the framework one")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1 && resultCode == RESULT_OK) apply()
        else if (requestCode == 1) text.text = "Myna needs to be the SMS app for a moment to delete or block. Nothing was changed."
    }

    private fun run(batch: JSONObject): JSONObject {
        val deleted = JSONArray()
        batch.optJSONArray("delete").forEachLong { id ->
            if (contentResolver.delete(ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id), null, null) > 0) deleted.put(id)
        }
        val read = ContentValues().apply { put(Telephony.Sms.READ, 1); put(Telephony.Sms.SEEN, 1) }
        batch.optJSONArray("read").forEachLong { id ->
            contentResolver.update(ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id), read, null, null)
        }
        batch.optJSONArray("block").forEachString { number ->
            contentResolver.insert(BlockedNumbers.CONTENT_URI, ContentValues().apply { put(BlockedNumbers.COLUMN_ORIGINAL_NUMBER, number) })
        }
        batch.optJSONArray("unblock").forEachString { number ->
            contentResolver.delete(BlockedNumbers.CONTENT_URI, "${BlockedNumbers.COLUMN_ORIGINAL_NUMBER} = ?", arrayOf(number))
        }
        val blocked = JSONArray()
        contentResolver.query(BlockedNumbers.CONTENT_URI, arrayOf(BlockedNumbers.COLUMN_ORIGINAL_NUMBER), null, null, null)?.use { c ->
            while (c.moveToNext()) blocked.put(c.getString(0))
        }
        return JSONObject().put("t", "sms.batch.done").put("id", batch.optString("id")).put("deleted", deleted).put("blocked", blocked)
    }

    companion object {
        /** Apps can't hand the SMS role to another app, and Samsung Messages doesn't ask for it back on its own: open Default apps. */
        fun handBack(activity: Activity) {
            android.widget.Toast.makeText(activity, "Tap SMS app, then Samsung Messages", android.widget.Toast.LENGTH_LONG).show()
            activity.startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        }

        fun summary(batch: JSONObject): String {
            val parts = listOfNotNull(
                batch.optJSONArray("delete")?.length()?.takeIf { it > 0 }?.let { "delete $it text${if (it == 1) "" else "s"}" },
                batch.optJSONArray("read")?.length()?.takeIf { it > 0 }?.let { "mark $it text${if (it == 1) "" else "s"} read" },
                batch.optJSONArray("block")?.length()?.takeIf { it > 0 }?.let { "block $it number${if (it == 1) "" else "s"}" },
                batch.optJSONArray("unblock")?.length()?.takeIf { it > 0 }?.let { "unblock $it number${if (it == 1) "" else "s"}" },
            )
            return parts.ifEmpty { listOf("check your blocked numbers") }.joinToString(", ")
        }
    }
}

private inline fun JSONArray?.forEachLong(f: (Long) -> Unit) { if (this != null) for (i in 0 until length()) f(getLong(i)) }
private inline fun JSONArray?.forEachString(f: (String) -> Unit) { if (this != null) for (i in 0 until length()) f(getString(i)) }
