package com.aengix.hopper.provision

import com.aengix.hopper.data.HopQRParser
import com.aengix.hopper.model.DeploySSHKey
import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.ssh.DeploySSH
import com.aengix.hopper.ssh.SSHKeyGenerator

sealed class ServerDeployerException(message: String) : Exception(message) {
    data object MissingHost : ServerDeployerException("Host is required.")
    data object MissingPassword : ServerDeployerException("Password is required.")
    data object MissingDeployKey : ServerDeployerException("Select a deploy key from the library.")
    data class SshFailed(val detail: String) : ServerDeployerException("SSH failed: $detail")
    data object EmptyResponse : ServerDeployerException("Server install did not return a profile JSON.")
    data class InvalidProfile(val detail: String) : ServerDeployerException("Invalid profile JSON: $detail")
}

sealed class ServerDeployAuth {
    data class Password(val password: String) : ServerDeployAuth()
    data class DeployKey(val key: DeploySSHKey) : ServerDeployAuth()
}

object ServerDeployer {
    data class Result(
        val profile: HopNodeProfile,
        val newDeployKey: DeploySSHKey?,
    )

    fun deploy(
        host: String,
        port: Int = HopConstants.DEFAULT_SSH_PORT,
        user: String = "root",
        installDir: String = HopConstants.DEFAULT_INSTALL_DIR,
        auth: ServerDeployAuth,
    ): Result {
        val trimmedHost = host.trim()
        if (trimmedHost.isEmpty()) throw ServerDeployerException.MissingHost

        val effectiveUser = user.trim().ifEmpty { "root" }

        val newKey: DeploySSHKey?
        val deployPrivateKey: String
        val password: String?

        when (auth) {
            is ServerDeployAuth.Password -> {
                if (auth.password.isEmpty()) throw ServerDeployerException.MissingPassword
                val generated = SSHKeyGenerator.generateEd25519("hopper-deploy@$trimmedHost")
                newKey = DeploySSHKey(
                    name = "Deploy $effectiveUser@$trimmedHost",
                    privateKey = generated.privateKeyPem,
                )
                deployPrivateKey = generated.privateKeyPem
                password = auth.password
            }
            is ServerDeployAuth.DeployKey -> {
                if (auth.key.privateKey.trim().isEmpty()) throw ServerDeployerException.MissingDeployKey
                newKey = null
                deployPrivateKey = auth.key.privateKey
                password = null
            }
        }

        val publicLine = runCatching {
            SSHKeyGenerator.publicKeyLine(deployPrivateKey, "deploy-$trimmedHost")
        }.getOrElse {
            throw ServerDeployerException.SshFailed("Could not derive deploy public key.")
        }

        val output = runCatching {
            DeploySSH.runInstall(
                host = trimmedHost,
                port = port,
                user = effectiveUser,
                password = password,
                privateKeyPem = deployPrivateKey,
                publicKeyLine = publicLine,
                installDir = installDir,
            )
        }.getOrElse { error ->
            throw ServerDeployerException.SshFailed(error.message ?: error.toString())
        }

        val jsonLine = extractJsonLine(output) ?: throw ServerDeployerException.EmptyResponse

        val profile = runCatching { HopQRParser.parse(jsonLine) }.getOrElse { error ->
            throw ServerDeployerException.InvalidProfile(error.message ?: "parse failed")
        }

        return Result(profile = profile, newDeployKey = newKey)
    }

    private fun extractJsonLine(output: String): String? =
        output.lineSequence().toList().asReversed().firstOrNull { line ->
            line.trim().startsWith("{")
        }?.trim()
}
