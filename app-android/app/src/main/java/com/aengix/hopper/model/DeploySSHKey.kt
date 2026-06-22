package com.aengix.hopper.model

import kotlinx.serialization.Serializable

@Serializable
data class DeploySSHKey(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String = "",
    val privateKey: String = "",
    val createdAt: Long = System.currentTimeMillis(),
)
