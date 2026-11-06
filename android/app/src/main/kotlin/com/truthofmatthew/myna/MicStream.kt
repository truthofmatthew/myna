package com.truthofmatthew.myna

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaRecorder

/** Mic → Opus (48 kHz mono, 32 kbit/s) → onPacket. Uses the call preset for echo cancelling. */
class MicStream(private val onPacket: (ptsMicros: Long, data: ByteArray) -> Unit) {
    @Volatile private var running = false
    private var thread: Thread? = null

    @SuppressLint("MissingPermission") // LinkService only runs after the user granted the mic
    fun start() {
        running = true
        thread = Thread({
            val chunk = ByteArray(RATE / 50 * 2) // 20 ms of 16-bit mono
            val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val record = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, chunk.size * 4))
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS)
            encoder.configure(MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_OPUS, RATE, 1).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, 32_000)
            }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            record.startRecording()
            val info = MediaCodec.BufferInfo()
            try {
                while (running) {
                    var read = 0
                    while (read < chunk.size && running) {
                        val n = record.read(chunk, read, chunk.size - read)
                        if (n < 0) return@Thread
                        read += n
                    }
                    val input = encoder.dequeueInputBuffer(10_000)
                    if (input >= 0) {
                        encoder.getInputBuffer(input)!!.apply { clear(); put(chunk, 0, read) }
                        encoder.queueInputBuffer(input, 0, read, System.nanoTime() / 1000, 0)
                    }
                    while (true) {
                        val output = encoder.dequeueOutputBuffer(info, 0)
                        if (output < 0) break
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0) {
                            val data = ByteArray(info.size)
                            encoder.getOutputBuffer(output)!!.apply { position(info.offset); get(data) }
                            runCatching { onPacket(info.presentationTimeUs, data) }
                        }
                        encoder.releaseOutputBuffer(output, false)
                    }
                }
            } finally {
                record.stop()
                record.release()
                runCatching { encoder.stop() }
                encoder.release()
            }
        }, "myna-mic").apply { start() }
    }

    fun stop() { running = false; thread = null }

    companion object { const val RATE = 48_000 }
}
