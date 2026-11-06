package com.truthofmatthew.myna

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Keeps the connection to the paired Mac and runs the camera and mic when the Mac asks.
 * A foreground service of type camera|microphone, so it can open them while the app is in the background.
 */
class LinkService : Service() {
    @Volatile private var running = false
    @Volatile private var link: Link? = null
    private var camera: CameraStream? = null
    private var mic: MicStream? = null
    private var texts: Texts? = null
    private var calls: Calls? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopSelf(); return START_NOT_STICKY }
        startForeground(1, notification("Looking for your Mac"), ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        if (!running) {
            running = true
            Thread(::connectLoop, "myna-link").start()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        link?.close()
        stopMedia()
        status = "Stopped"
    }

    private fun connectLoop() {
        while (running) {
            val pairing = Pairing.load(this) ?: run { setStatus("Not paired"); stopSelf(); return }
            // The Mac is only reachable on the local network; never let Android send this over mobile data.
            val cm = getSystemService(ConnectivityManager::class.java)
            @Suppress("DEPRECATION") // allNetworks is the simplest way to pick the Wi-Fi network once
            // Samsung keeps extra, restricted Wi-Fi networks (Quick Share and the like); binding to one fails with EPERM.
            val wifi = cm.allNetworks.firstOrNull {
                cm.getNetworkCapabilities(it)?.run {
                    hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                } == true
            }
            if (wifi == null) { setStatus("Turn on Wi-Fi to reach ${pairing.name}"); Thread.sleep(3000); continue }
            try {
                val address = discover(pairing) ?: InetSocketAddress(pairing.host, pairing.port)
                setStatus("Connecting to ${pairing.name}")
                val socket = Socket()
                // Android sometimes refuses the pin with EPERM for a while (seen after a reinstall); the default route still reaches the Mac then.
                runCatching { wifi.bindSocket(socket) }.onFailure { Log.i(TAG, "not pinned to Wi-Fi: $it") }
                socket.apply { connect(address, 5000); soTimeout = 30_000; tcpNoDelay = true }
                Link(socket, pairing.key).use { l ->
                    link = l
                    active = l
                    l.sendMessage(JSONObject().put("t", "hello").put("name", deviceName()).put("app", 1))
                    texts = Texts(this) { runCatching { l.sendMessage(it) } }.also { it.start() }
                    calls = Calls(this) { runCatching { l.sendMessage(it) } }.also { it.start() }
                    setStatus("Connected to ${pairing.name}")
                    while (running) {
                        val (type, body) = l.receive()
                        if (type == TYPE_MESSAGE) handle(l, JSONObject(String(body)))
                    }
                }
            } catch (e: Exception) {
                Log.i(TAG, "connection ended: $e")
            } finally {
                link = null
                active = null
                texts?.stop(); texts = null
                calls?.stop(); calls = null
                stopMedia()
            }
            if (running) { setStatus("Waiting for ${Pairing.load(this)?.name ?: "your Mac"}"); Thread.sleep(2000) }
        }
    }

    private fun handle(l: Link, message: JSONObject) {
        val t = message.optString("t")
        if (t.startsWith("sms.")) { texts?.handle(message); return }
        if (t.startsWith("call.")) { calls?.handle(message); return }
        when (t) {
            "ping" -> l.sendMessage(JSONObject().put("t", "pong"))
            "camera" -> {
                camera?.stop(); camera = null
                if (message.optBoolean("on")) {
                    camera = CameraStream(this, message.optString("camera") != "back",
                        onPacket = { flags, pts, data -> l.sendMedia(TYPE_VIDEO, flags, pts, data) },
                        onRotation = { w, h, r -> l.sendMessage(JSONObject().put("t", "video").put("w", w).put("h", h).put("rotation", r)) },
                    ).also { it.start() }
                }
            }
            "keyframe" -> camera?.run { requestKeyFrame(); announce() }
            "mic" -> {
                mic?.stop(); mic = null
                if (message.optBoolean("on")) mic = MicStream { pts, data -> l.sendMedia(TYPE_AUDIO, 0, pts, data) }.also { it.start() }
            }
        }
    }

    private fun stopMedia() {
        camera?.stop(); camera = null
        mic?.stop(); mic = null
    }

    /** Finds the paired Mac over Bonjour by its id; null if it doesn't show up within 3 s. */
    private fun discover(pairing: Pairing): InetSocketAddress? {
        val nsd = getSystemService(NsdManager::class.java)
        val found = CountDownLatch(1)
        var result: InetSocketAddress? = null
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION") // registerServiceInfoCallback is overkill for a one-shot lookup
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        val id = resolved.attributes["id"]?.let { String(it) }
                        val host = resolved.hostAddresses.firstOrNull()
                        if (id == pairing.id && host != null) { result = InetSocketAddress(host, resolved.port); found.countDown() }
                    }
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) = Unit
                })
            }
            override fun onServiceLost(info: NsdServiceInfo) = Unit
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, errorCode: Int) { found.countDown() }
            override fun onStopDiscoveryFailed(type: String, errorCode: Int) = Unit
        }
        nsd.discoverServices("_myna._tcp", NsdManager.PROTOCOL_DNS_SD, listener)
        found.await(3, TimeUnit.SECONDS)
        runCatching { nsd.stopServiceDiscovery(listener) }
        return result
    }

    private fun setStatus(text: String) {
        status = text
        getSystemService(NotificationManager::class.java).notify(1, notification(text))
    }

    private fun notification(text: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Connection to your Mac", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, LinkService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("Myna")
            .setContentText(text)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Disconnect", stop).build())
            .setOngoing(true)
            .build()
    }

    private fun deviceName() = android.provider.Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL

    companion object {
        private const val TAG = "MynaLink"
        private const val CHANNEL = "link"
        private const val ACTION_STOP = "stop"
        @Volatile var status = "Stopped"
        @Volatile private var active: Link? = null

        /** For parts of the app outside the connection loop; dropped if the Mac isn't connected. */
        fun sendToMac(message: JSONObject) { runCatching { active?.sendMessage(message) } }

        fun start(context: Context) = context.startForegroundService(Intent(context, LinkService::class.java))
        fun stop(context: Context) = context.stopService(Intent(context, LinkService::class.java))
    }
}
