package com.aengix.hopper.vpn

import android.app.Application
import android.content.Intent
import android.net.VpnService
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.aengix.hopper.data.DemoProfiles
import com.aengix.hopper.data.ProfileStore
import com.aengix.hopper.model.AppState
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.provision.ChainProvisioner
import com.aengix.hopper.util.HopErrorDetails
import com.aengix.hopper.util.TunnelLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class VpnController(application: Application) : AndroidViewModel(application) {
    private val _state = MutableStateFlow(ProfileStore.load())
    val state: StateFlow<AppState> = _state.asStateFlow()

    var onVpnPermissionRequired: ((Intent) -> Unit)? = null

    private val _vpnStatus = MutableStateFlow(VpnStatus.Disconnected)
    val vpnStatus: StateFlow<VpnStatus> = _vpnStatus.asStateFlow()

    private val _provisionStatus = MutableStateFlow<String?>(null)
    val provisionStatus: StateFlow<String?> = _provisionStatus.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val statusListener: (VpnStatus, String?) -> Unit = { status, error ->
        _vpnStatus.value = status
        if (error != null) {
            _errorMessage.value = HopErrorDetails.describeMessage(error)
        }
    }

    init {
        VpnStatusBus.addListener(statusListener)
    }

    val isConnected: Boolean get() = _vpnStatus.value == VpnStatus.Connected
    val isBusy: Boolean
        get() = _vpnStatus.value == VpnStatus.Connecting ||
            _vpnStatus.value == VpnStatus.Disconnecting

    fun addServer(server: HopNodeProfile) {
        updateState { it.addServer(server) }
    }

    fun deleteServers(ids: Set<String>) {
        updateState { it.removeServers(ids) }
    }

    fun renameServer(id: String, name: String) {
        updateState { it.renameServer(id, name) }
    }

    fun addChain(name: String = ""): String {
        var chainId = ""
        updateState {
            val (next, id) = it.addChain(name)
            chainId = id
            next
        }
        return chainId
    }

    fun deleteChains(ids: Set<String>) {
        updateState { it.removeChains(ids) }
    }

    fun selectChain(id: String?) {
        updateState { it.selectChain(id) }
    }

    fun loadDemoData() {
        updateState { DemoProfiles.appState() }
    }

    fun renameChain(id: String, name: String) {
        updateState { it.renameChain(id, name) }
    }

    fun moveHopInChain(chainID: String, fromIndex: Int, toIndex: Int) {
        updateState { it.moveHopInChain(chainID, fromIndex, toIndex) }
    }

    fun addServerToChain(chainID: String, serverID: String) {
        updateState { it.addServerToChain(chainID, serverID) }
    }

    fun removeHopFromChain(chainID: String, indices: Set<Int>) {
        updateState { it.removeHopFromChain(chainID, indices) }
    }

    fun setError(message: String?) {
        _errorMessage.value = message
    }

    fun connect(restartHopperd: Boolean = false) {
        val entry = _state.value.entryHop
        if (entry == null) {
            reportError("Select a chain with at least one server (entry → exit).")
            return
        }

        _errorMessage.value = null
        _provisionStatus.value = null
        ProfileStore.clearLastTunnelError()

        val hops = _state.value.activeHops
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    _provisionStatus.value = "Provisioning chain (exit → entry)…"
                    ChainProvisioner.provision(chain = hops, restartHopperd = restartHopperd) { index, total, message ->
                        _provisionStatus.value = "[${total - index}/$total] $message"
                    }
                }

                _provisionStatus.value = "Starting VPN…"
                val context = getApplication<android.app.Application>()
                val prepareIntent = VpnService.prepare(context)
                if (prepareIntent != null) {
                    PendingVpnConnect.pendingHopJson = TunnelBootstrap.hopJson(entry)
                    _provisionStatus.value = null
                    if (PendingVpnConnect.permissionGranted) {
                        completePendingConnect()
                    } else {
                        TunnelLog.info("VPN permission required — requesting consent")
                        onVpnPermissionRequired?.invoke(prepareIntent)
                            ?: TunnelLog.error("VPN permission required but no handler registered")
                    }
                    return@launch
                }

                startVpnService(entry)
                _provisionStatus.value = null
            } catch (error: Throwable) {
                _provisionStatus.value = null
                reportError(HopErrorDetails.describe(error))
            }
        }
    }

    fun onVpnPermissionGranted() {
        PendingVpnConnect.permissionGranted = true
        TunnelLog.info("VPN permission granted")
        completePendingConnect()
    }

    private fun completePendingConnect() {
        val hopJson = PendingVpnConnect.pendingHopJson ?: return
        PendingVpnConnect.clear()
        val hop = kotlinx.serialization.json.Json.decodeFromString(HopNodeProfile.serializer(), hopJson)
        startVpnService(hop)
    }

    fun disconnect() {
        val context = getApplication<android.app.Application>()
        context.startService(
            Intent(context, HopperVpnService::class.java).apply {
                action = HopperVpnService.ACTION_DISCONNECT
            },
        )
        _vpnStatus.value = VpnStatus.Disconnecting
    }

    fun readTunnelErrorIfNeeded() {
        ProfileStore.loadLastTunnelError()?.let { reportError(it) }
    }

    private fun startVpnService(entry: HopNodeProfile) {
        val context = getApplication<android.app.Application>()
        context.startForegroundService(
            Intent(context, HopperVpnService::class.java).apply {
                action = HopperVpnService.ACTION_CONNECT
                putExtra(HopperVpnService.EXTRA_HOP_JSON, TunnelBootstrap.hopJson(entry))
            },
        )
    }

    private fun updateState(block: (AppState) -> AppState) {
        _state.update { current ->
            val next = block(current)
            ProfileStore.save(next)
            next
        }
    }

    private fun reportError(message: String) {
        val detail = HopErrorDetails.describeMessage(message)
        _errorMessage.value = detail
        TunnelLog.error("[App] $detail")
    }

    override fun onCleared() {
        VpnStatusBus.removeListener(statusListener)
        super.onCleared()
    }
}

object PendingVpnConnect {
    var pendingHopJson: String? = null
    @Volatile var permissionGranted: Boolean = false

    fun clear() {
        pendingHopJson = null
        permissionGranted = false
    }
}
