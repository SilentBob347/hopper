package com.aengix.hopper.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.aengix.hopper.vpn.VpnController

object Routes {
    const val HOME = "home"
    const val CHAINS = "chains"
    const val CHAIN_DETAIL = "chain/{chainId}"
    const val SERVERS = "servers"
    const val SERVER_DETAIL = "server/{serverId}"

    fun chainDetail(chainId: String) = "chain/$chainId"
    fun serverDetail(serverId: String) = "server/$serverId"
}

@Composable
fun HopperNavHost(
    navController: NavHostController = rememberNavController(),
    vpn: VpnController,
    onRequestVpnConnect: (restartHopperd: Boolean) -> Unit,
    onRequestCameraPermission: (onGranted: () -> Unit) -> Unit,
    startDestination: String = Routes.HOME,
) {
    NavHost(navController = navController, startDestination = startDestination) {
        composable(Routes.HOME) {
            HomeScreen(
                vpn = vpn,
                onConfigureChains = { navController.navigate(Routes.CHAINS) },
                onChainDetail = { chainId ->
                    navController.navigate(Routes.chainDetail(chainId))
                },
                onRequestVpnConnect = onRequestVpnConnect,
            )
        }
        composable(Routes.CHAINS) {
            ChainConfiguratorScreen(
                vpn = vpn,
                onBack = { navController.popBackStack() },
                onChainDetail = { chainId ->
                    navController.navigate(Routes.chainDetail(chainId))
                },
                onOpenServers = { navController.navigate(Routes.SERVERS) },
            )
        }
        composable(Routes.CHAIN_DETAIL) { backStackEntry ->
            val chainId = backStackEntry.arguments?.getString("chainId").orEmpty()
            ChainDetailScreen(
                vpn = vpn,
                chainId = chainId,
                onBack = { navController.popBackStack() },
            )
        }
        composable(Routes.SERVERS) {
            ServerLibraryScreen(
                vpn = vpn,
                onBack = { navController.popBackStack() },
                onServerDetail = { serverId ->
                    navController.navigate(Routes.serverDetail(serverId))
                },
                onRequestCameraPermission = onRequestCameraPermission,
            )
        }
        composable(Routes.SERVER_DETAIL) { backStackEntry ->
            val serverId = backStackEntry.arguments?.getString("serverId").orEmpty()
            ServerDetailScreen(
                vpn = vpn,
                serverId = serverId,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
