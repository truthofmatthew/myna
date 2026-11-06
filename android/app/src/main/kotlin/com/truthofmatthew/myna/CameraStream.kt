package com.truthofmatthew.myna

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.view.OrientationEventListener

/**
 * Camera → hardware H.264 encoder → onPacket. Frames go out as the sensor gives them (landscape);
 * onRotation reports the clockwise turn the viewer should apply, and follows the phone as it turns.
 */
class CameraStream(
    private val context: Context,
    front: Boolean,
    private val onPacket: (flags: Int, ptsMicros: Long, data: ByteArray) -> Unit,
    private val onRotation: (width: Int, height: Int, rotation: Int) -> Unit,
) {
    private val manager = context.getSystemService(CameraManager::class.java)
    private val cameraId = manager.cameraIdList.first {
        manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
            if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
    }
    private val characteristics = manager.getCameraCharacteristics(cameraId)
    private val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
    private val isFront = front
    private val thread = HandlerThread("myna-camera").apply { start() }
    private val handler = Handler(thread.looper)
    private val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private var camera: CameraDevice? = null
    private var rotation = -1

    private val orientation = object : OrientationEventListener(context) {
        override fun onOrientationChanged(degrees: Int) {
            if (degrees == ORIENTATION_UNKNOWN) return
            val device = (degrees + 45) / 90 % 4 * 90
            // Same rule Android uses for JPEG orientation.
            val turn = if (isFront) (sensorOrientation + device) % 360 else (sensorOrientation - device + 360) % 360
            if (turn != rotation) { rotation = turn; onRotation(WIDTH, HEIGHT, turn) }
        }
    }

    @SuppressLint("MissingPermission") // LinkService only runs after the user granted the camera
    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, WIDTH, HEIGHT).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_PRIORITY, 0) // realtime
        }
        encoder.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) = Unit // input is a Surface
            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                val buffer = codec.getOutputBuffer(index) ?: return
                val data = ByteArray(info.size).also { buffer.position(info.offset); buffer.get(it) }
                codec.releaseOutputBuffer(index, false)
                var flags = 0
                if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) flags = flags or FLAG_KEY
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) flags = flags or FLAG_CONFIG
                runCatching { onPacket(flags, info.presentationTimeUs, data) }
            }
            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) { Log.w(TAG, "encoder", e) }
            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) = Unit
        }, handler)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = encoder.createInputSurface()
        encoder.start()

        val executor = { r: Runnable -> handler.post(r); Unit }
        manager.openCamera(cameraId, executor, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                camera = device
                val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    addTarget(surface)
                    set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(FPS, FPS))
                }.build()
                device.createCaptureSession(SessionConfiguration(SessionConfiguration.SESSION_REGULAR,
                    listOf(OutputConfiguration(surface)), executor, object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) { session.setRepeatingRequest(request, null, handler) }
                        override fun onConfigureFailed(session: CameraCaptureSession) { Log.w(TAG, "capture session failed") }
                    }))
            }
            override fun onDisconnected(device: CameraDevice) = device.close()
            override fun onError(device: CameraDevice, error: Int) { Log.w(TAG, "camera error $error"); device.close() }
        })
        orientation.enable()
    }

    /** Re-sends the current rotation; for a viewer that just joined. */
    fun announce() { if (rotation >= 0) onRotation(WIDTH, HEIGHT, rotation) }

    fun requestKeyFrame() = runCatching {
        encoder.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
    }

    fun stop() {
        orientation.disable()
        handler.post {
            camera?.close()
            runCatching { encoder.stop() }
            encoder.release()
            thread.quitSafely()
        }
    }

    companion object {
        private const val TAG = "MynaCamera"
        const val WIDTH = 1280
        const val HEIGHT = 720
        private const val FPS = 30
    }
}
