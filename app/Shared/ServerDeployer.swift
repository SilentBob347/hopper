import Foundation

enum ServerDeployerError: LocalizedError {
    case missingHost
    case missingPassword
    case missingDeployKey
    case sshFailed(String)
    case emptyResponse
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .missingHost: return "Host is required."
        case .missingPassword: return "Password is required."
        case .missingDeployKey: return "Select a deploy key from the library."
        case .sshFailed(let detail): return "SSH failed: \(detail)"
        case .emptyResponse: return "Server install did not return a profile JSON."
        case .invalidProfile(let detail): return "Invalid profile JSON: \(detail)"
        }
    }
}

enum ServerDeployAuth {
    case password(String)
    case deployKey(DeploySSHKey)
}

enum ServerDeployer {
    struct Result {
        let profile: HopNodeProfile
        let newDeployKey: DeploySSHKey?
    }

    static func deploy(
        host: String,
        port: Int = HopConstants.defaultSSHPort,
        user: String = "root",
        installDir: String = HopConstants.defaultInstallDir,
        auth: ServerDeployAuth,
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { throw ServerDeployerError.missingHost }

        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveUser = trimmedUser.isEmpty ? "root" : trimmedUser

        var newKey: DeploySSHKey?
        let deployPrivateKey: String
        let connectPassword: String?

        switch auth {
        case .password(let password):
            guard !password.isEmpty else { throw ServerDeployerError.missingPassword }
            let generated = try SSHKeyGenerator.generateEd25519(comment: "hopper-deploy@\(trimmedHost)")
            let key = DeploySSHKey(
                name: "Deploy \(effectiveUser)@\(trimmedHost)",
                privateKey: generated.privateKeyPEM
            )
            newKey = key
            deployPrivateKey = generated.privateKeyPEM
            connectPassword = password
        case .deployKey(let key):
            guard !key.privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServerDeployerError.missingDeployKey
            }
            deployPrivateKey = key.privateKey
            connectPassword = nil
        }

        let publicLine: String
        do {
            publicLine = try SSHKeyGenerator.publicKeyLine(
                privateKeyPEM: deployPrivateKey,
                comment: "deploy-\(trimmedHost)"
            )
        } catch {
            throw ServerDeployerError.sshFailed("Could not derive deploy public key.")
        }

        let output: String
        do {
            output = try await DeploySSH.runInstall(
                host: trimmedHost,
                port: port,
                user: effectiveUser,
                password: connectPassword,
                privateKeyPEM: deployPrivateKey,
                publicKeyLine: publicLine,
                installDir: installDir,
                onLog: onLog
            )
        } catch {
            throw ServerDeployerError.sshFailed(error.localizedDescription)
        }

        guard let jsonLine = extractJSONLine(from: output) else {
            throw ServerDeployerError.emptyResponse
        }

        let profile: HopNodeProfile
        do {
            profile = try HopQRParser.parse(jsonLine)
        } catch {
            throw ServerDeployerError.invalidProfile(error.localizedDescription)
        }

        return Result(profile: profile, newDeployKey: newKey)
    }

    private static func extractJSONLine(from output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                return trimmed
            }
        }
        return nil
    }
}
