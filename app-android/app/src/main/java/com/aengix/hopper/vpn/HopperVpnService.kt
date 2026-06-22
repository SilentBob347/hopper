package com.aengix.hopper.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.core.app.NotificationCompat
import com.aengix.hopper.MainActivity
import com.aengix.hopper.R
import com.aengix.hopper.data.ProfileStore
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.util.HopErrorDetails
import com.aengix.hopper.util.TunnelLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

class HopperVpnService : VpnService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val coordinator = TunnelCoordinator(this)
    private val tunnelMutex = Mutex()
    private var tunnelJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val hopJson = intent.getStringExtra(EXTRA_HOP_JSON)
                val contextJson = intent.getStringExtra(EXTRA_CONTEXT_JSON)
                if (hopJson.isNullOrBlank() || contextJson.isNullOrBlank()) {
                    failTunnel("Tunnel start options did not include hop or chain context.")
                    return START_NOT_STICKY
                }
                val hop = runCatching {
                    Json.decodeFromString(HopNodeProfile.serializer(), hopJson)
                }.getOrElse {
                    failTunnel(HopErrorDetails.describe(it))
                    return START_NOT_STICKY
                }
                val context = runCatching {
                    Json.decodeFromString<com.aengix.hopper.model.TunnelConnectContext>(contextJson)
                }.getOrElse {
                    failTunnel(HopErrorDetails.describe(it))
                    return START_NOT_STICKY
                }
                startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.vpn_notification_connecting)))
                ProfileStore.clearLastTunnelError()
                VpnStatusBus.update(VpnStatus.Connecting)
                tunnelJob?.cancel()
                tunnelJob = scope.launch { runTunnel(hop, context) }
            }
            ACTION_DISCONNECT -> {
                stopTunnelInternal(userInitiated = true)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTunnelInternal(userInitiated = true)
        scope.cancel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnelInternal(userInitiated = true)
        super.onRevoke()
    }

    private suspend fun runTunnel(hop: HopNodeProfile, context: com.aengix.hopper.model.TunnelConnectContext) {
        tunnelMutex.withLock {
            coordinator.onSessionFailure = { message ->
                scope.launch {
                    failTunnel(message)
                    stopSelf()
                }
            }

            try {
                val prepared = coordinator.prepare(hop, context)
                startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.vpn_notification_text)))
                coordinator.startRelay(prepared.tunInterface)
                VpnStatusBus.update(VpnStatus.Connected)
            } catch (error: CancellationException) {
                coordinator.stop()
                throw error
            } catch (error: Throwable) {
                failTunnel(HopErrorDetails.describe(error))
                stopSelf()
            }
        }
    }

    private fun stopTunnelInternal(userInitiated: Boolean) {
        tunnelJob?.cancel()
        tunnelJob = null
        coordinator.stop()
        if (!userInitiated) {
            ProfileStore.saveLastTunnelError("Tunnel stopped unexpectedly")
        }
        VpnStatusBus.update(VpnStatus.Disconnected)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun failTunnel(detail: String) {
        TunnelLog.error("Tunnel failed: $detail")
        ProfileStore.saveLastTunnelError(detail)
        coordinator.stop()
        VpnStatusBus.update(VpnStatus.Disconnected, detail)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.vpn_notification_title),
            NotificationManager.IMPORTANCE_LOW,
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.vpn_notification_title))
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_CONNECT = "com.aengix.hopper.CONNECT"
        const val ACTION_DISCONNECT = "com.aengix.hopper.DISCONNECT"
        const val EXTRA_HOP_JSON = "hop_json"
        const val EXTRA_CONTEXT_JSON = "context_json"

        private const val CHANNEL_ID = "hopper_vpn"
        private const val NOTIFICATION_ID = 1
    }
}

enum class VpnStatus {
    Disconnected,
    Connecting,
    Connected,
    Disconnecting,
}

object VpnStatusBus {
    private val listeners = mutableSetOf<(VpnStatus, String?) -> Unit>()

    @Volatile
    var current: VpnStatus = VpnStatus.Disconnected
        private set

    @Volatile
    var lastError: String? = null
        private set

    fun update(status: VpnStatus, error: String? = null) {
        current = status
        if (error != null) lastError = error
        listeners.forEach { it(status, error) }
    }

    fun addListener(listener: (VpnStatus, String?) -> Unit) {
        listeners += listener
        listener(current, lastError)
    }

    fun removeListener(listener: (VpnStatus, String?) -> Unit) {
        listeners -= listener
    }
}
