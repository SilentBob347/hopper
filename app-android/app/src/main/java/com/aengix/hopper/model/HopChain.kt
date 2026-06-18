package com.aengix.hopper.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HopChain(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val hopIDs: List<String> = emptyList(),
) {
    val trimmedName: String get() = name.trim()

    val displayName: String
        get() = trimmedName.ifEmpty { "Untitled chain" }
}
