package com.truthofmatthew.myna

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder

/** Mic → 20 ms chunks of 48 kHz mono 16-bit PCM → onChunk. Uses the call preset for echo cancelling. */
class MicStream(private val onChunk: (ptsMicros: Long, data: ByteArray) -> Unit) {
    @Volatile private var running = false
    private var thread: Thread? = null

    // shortcut: raw PCM is ~770 kbit/s, fine on a home network; switch to Opus if Wi-Fi gets tight.
    @SuppressLint("MissingPermission") // LinkService only runs after the user granted the mic
    fun start() {
        running = true
        thread = Thread({
            val chunk = ByteArray(RATE / 50 * 2)
            val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val record = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, chunk.size * 4))
            record.startRecording()
            try {
                while (running) {
                    var read = 0
                    while (read < chunk.size && running) {
                        val n = record.read(chunk, read, chunk.size - read)
                        if (n < 0) return@Thread
                        read += n
                    }
                    runCatching { onChunk(System.nanoTime() / 1000, chunk.copyOf()) }
                }
            } finally {
                record.stop()
                record.release()
            }
        }, "myna-mic").apply { start() }
    }

    fun stop() { running = false; thread = null }

    companion object { const val RATE = 48_000 }
}
