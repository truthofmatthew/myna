package com.truthofmatthew.myna

import android.content.Context
import android.net.Uri
import android.util.Base64
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.Socket
import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

const val TYPE_MESSAGE = 1
const val TYPE_VIDEO = 2
const val TYPE_AUDIO = 3
const val FLAG_KEY = 1
const val FLAG_CONFIG = 2
private const val MAX_FRAME = 4 shl 20

/** The Mac this phone is paired with, from the QR link (see docs/PROTOCOL.md). */
data class Pairing(val id: String, val name: String, val host: String, val port: Int, val key: ByteArray) {
    fun save(context: Context) = prefs(context).edit()
        .putString("id", id).putString("name", name).putString("host", host).putInt("port", port)
        .putString("key", Base64.encodeToString(key, Base64.NO_WRAP)).apply()

    companion object {
        private fun prefs(context: Context) = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)

        fun load(context: Context): Pairing? {
            val p = prefs(context)
            val key = p.getString("key", null) ?: return null
            return Pairing(p.getString("id", "")!!, p.getString("name", "")!!, p.getString("host", "")!!,
                p.getInt("port", 0), Base64.decode(key, Base64.NO_WRAP))
        }

        fun forget(context: Context) = prefs(context).edit().clear().apply()

        /** Parses myna://pair?id=…&n=…&h=…&p=…&k=…, or returns null if anything is missing or malformed. */
        fun parse(uri: Uri): Pairing? {
            if (uri.scheme != "myna" || uri.host != "pair") return null
            val key = runCatching { Base64.decode(uri.getQueryParameter("k"), Base64.URL_SAFE or Base64.NO_PADDING) }.getOrNull()
            val port = uri.getQueryParameter("p")?.toIntOrNull()
            val id = uri.getQueryParameter("id")
            val host = uri.getQueryParameter("h")
            if (key == null || key.size != 32 || port == null || port !in 1..65535 || id.isNullOrEmpty() || host.isNullOrEmpty()) return null
            return Pairing(id, uri.getQueryParameter("n") ?: "Mac", host, port, key)
        }
    }
}

/** One encrypted connection to the Mac: handshake, then AES-256-GCM frames with per-direction counters. */
class Link(private val socket: Socket, pairingKey: ByteArray) : Closeable {
    private val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
    private val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
    private val sendKey: SecretKeySpec
    private val receiveKey: SecretKeySpec
    private var sendCounter = 0L
    private var receiveCounter = 0L

    init {
        val phoneNonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
        output.write("MYNA".toByteArray())
        output.write(1)
        output.write(phoneNonce)
        output.write(ByteArray(11))
        output.flush()
        val macNonce = ByteArray(16).also { input.readFully(it) }
        val salt = phoneNonce + macNonce
        sendKey = SecretKeySpec(hkdf(pairingKey, salt, "myna1 phone to mac"), "AES")
        receiveKey = SecretKeySpec(hkdf(pairingKey, salt, "myna1 mac to phone"), "AES")
    }

    fun send(type: Int, body: ByteArray) = synchronized(this) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, sendKey, GCMParameterSpec(128, nonce(sendCounter++)))
        val sealed = cipher.doFinal(byteArrayOf(type.toByte()) + body)
        output.writeInt(sealed.size)
        output.write(sealed)
        output.flush()
    }

    fun sendMessage(message: JSONObject) = send(TYPE_MESSAGE, message.toString().toByteArray())

    fun sendMedia(type: Int, flags: Int, ptsMicros: Long, data: ByteArray, offset: Int = 0, length: Int = data.size) =
        send(type, ByteBuffer.allocate(9 + length).put(flags.toByte()).putLong(ptsMicros).put(data, offset, length).array())

    /** Blocks for the next frame; returns its type and body. Throws on a bad or tampered frame. */
    fun receive(): Pair<Int, ByteArray> {
        val length = input.readInt()
        if (length !in 17..MAX_FRAME) throw IOException("bad frame length $length")
        val sealed = ByteArray(length).also { input.readFully(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, receiveKey, GCMParameterSpec(128, nonce(receiveCounter++)))
        val plain = cipher.doFinal(sealed)
        return plain[0].toInt() to plain.copyOfRange(1, plain.size)
    }

    override fun close() = socket.close()

    private fun nonce(counter: Long) = ByteBuffer.allocate(12).putInt(0).putLong(counter).array()
}

/** HKDF-SHA256 with a single 32-byte output block. */
fun hkdf(ikm: ByteArray, salt: ByteArray, info: String): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(salt, "HmacSHA256"))
    val prk = mac.doFinal(ikm)
    mac.init(SecretKeySpec(prk, "HmacSHA256"))
    mac.update(info.toByteArray())
    mac.update(1)
    return mac.doFinal()
}
