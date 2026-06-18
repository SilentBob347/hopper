package com.aengix.hopper

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.navigation.compose.rememberNavController
import com.aengix.hopper.ui.HopperNavHost
import com.aengix.hopper.util.TunnelLog
import com.aengix.hopper.vpn.VpnController

class MainActivity : ComponentActivity() {
    private val vpnController: VpnController by viewModels()

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            pendingVpnAction?.invoke() ?: vpnController.onVpnPermissionGranted()
            pendingVpnAction = null
        } else {
            pendingVpnAction = null
            vpnController.setError("VPN permission was denied.")
        }
    }

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            pendingCameraScan?.invoke()
        } else {
            vpnController.setError("Camera permission is required to scan QR codes.")
        }
        pendingCameraScan = null
    }

    private var pendingVpnAction: (() -> Unit)? = null
    private var pendingCameraScan: (() -> Unit)? = null

    fun requestVpnConnect(restartHopperd: Boolean) {
        requestVpnPermission {
            vpnController.connect(restartHopperd = restartHopperd)
        }
    }

    private fun requestVpnPermission(onGranted: () -> Unit) {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent == null) {
            onGranted()
            return
        }
        TunnelLog.info("Launching VPN permission dialog")
        pendingVpnAction = onGranted
        vpnPermissionLauncher.launch(prepareIntent)
    }

    fun requestCameraPermission(onGranted: () -> Unit) {
        when {
            checkSelfPermission(android.Manifest.permission.CAMERA) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED -> onGranted()
            else -> {
                pendingCameraScan = onGranted
                cameraPermissionLauncher.launch(android.Manifest.permission.CAMERA)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, true)

        vpnController.onVpnPermissionRequired = { intent ->
            TunnelLog.info("Launching VPN permission dialog after provisioning")
            vpnPermissionLauncher.launch(intent)
        }

        setContent {
            val navController = rememberNavController()
            MaterialTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    HopperNavHost(
                        navController = navController,
                        vpn = vpnController,
                        onRequestVpnConnect = ::requestVpnConnect,
                        onRequestCameraPermission = ::requestCameraPermission,
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        vpnController.readTunnelErrorIfNeeded()
    }
}
