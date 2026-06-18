package com.aengix.hopper.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HopNodeProfile(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val host: String = "",
    val port: Int = HopConstants.DEFAULT_SSH_PORT,
    val user: String = "",
    val privateKey: String = "",
    val hostKeys: List<String> = emptyList(),
    val installDir: String = "",
) {
    val trimmedName: String get() = name.trim()
    val trimmedHost: String get() = host.trim()
    val trimmedUser: String get() = user.trim()

    val displayName: String
        get() = when {
            trimmedName.isNotEmpty() -> trimmedName
            trimmedHost.isNotEmpty() -> trimmedHost
            else -> "Untitled"
        }

    val resolvedInstallDir: String
        get() = installDir.trim().ifEmpty { HopConstants.DEFAULT_INSTALL_DIR }
}
