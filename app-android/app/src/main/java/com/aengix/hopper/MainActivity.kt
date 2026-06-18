package com.aengix.hopper

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.navigation.compose.rememberNavController
import com.aengix.hopper.ui.HopperNavHost
import com.aengix.hopper.vpn.PendingVpnConnect
import com.aengix.hopper.vpn.VpnController

class MainActivity : ComponentActivity() {
    private val vpnController: VpnController by viewModels()

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            vpnController.onVpnPermissionGranted()
        } else {
            vpnController.setError("VPN permission was denied.")
        }
    }

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (!granted) {
            vpnController.setError("Camera permission is required to scan QR codes.")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)

        setContent {
            val navController = rememberNavController()
            MaterialTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    HopperNavHost(
                        navController = navController,
                        vpn = vpnController,
                        onRequestVpnPermission = vpnPermissionLauncher::launch,
                        onRequestCameraPermission = {
                            when {
                                ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                                    PackageManager.PERMISSION_GRANTED -> true
                                else -> {
                                    cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                                    false
                                }
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        vpnController.readTunnelErrorIfNeeded()
        if (PendingVpnConnect.requestPermission) {
            val intent = VpnService.prepare(this)
            if (intent != null) {
                vpnPermissionLauncher.launch(intent)
            } else {
                vpnController.onVpnPermissionGranted()
            }
        }
    }
}
