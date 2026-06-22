import Foundation

enum HopErrorDetails {
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return describe(underlying)
        }

        if ns.domain.contains("NIOSSH") {
            return friendlyOpaqueNIOSSH(ns)
        }

        if let stream = friendlySSHByteStreamError(error) {
            return stream
        }

        if let tunnel = friendlyIPTunnelProtocolError(error) {
            return tunnel
        }

        if let hopper = friendlyHopperExtensionError(ns, error: error) {
            return hopper
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty,
           !description.contains("NIOSSH.NIOSSHError") {
            return description
        }

        let rendered = String(describing: error)
        if rendered.contains("NIOSSHError") || rendered.contains("NIOSSH.NIOSSHError") {
            return friendlyOpaqueNIOSSH(ns, rendered: rendered)
        }

        if ns.domain == "NEVPNErrorDomain" && ns.code == 1 {
            return """
            VPN configuration is invalid — the tunnel extension may not be embedded in the app. \
            Clean build, delete the app, reinstall from Xcode, then try again.
            """
        }

        if ns.domain == "NEVPNConnectionErrorDomain" && ns.code == 12 {
            return """
            VPN session ended unexpectedly (internal error). \
            Usually the tunnel extension was killed by iOS or the SSH session dropped. \
            Wait a few seconds, then reconnect.
            """
        }

        return describeText(rendered, fallback: error.localizedDescription)
    }

    static func describeMessage(_ message: String) -> String {
        if message.contains("NIOSSH") || message.contains("NEVPNConnectionErrorDomain") {
            let fake = NSError(domain: "NIOSSH.NIOSSHError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
            return describe(fake)
        }
        return message
    }

    private static func friendlyOpaqueNIOSSH(_ error: NSError, rendered: String? = nil) -> String {
        let detail = rendered ?? String(describing: error)
        if detail.contains("keyExchangeNegotiationFailure") {
            return "SSH key exchange failed — server must offer curve25519-sha256 or ecdh-sha2-nistp256. (\(detail))"
        }
        if detail.contains("channelSetupRejected") {
            return "SSH channel rejected — is hopperd running? Check: pgrep -af hopperd on the server. (\(detail))"
        }
        if detail.contains("invalidUserAuthSignature") {
            return "SSH authentication failed — re-scan the hop QR code. (\(detail))"
        }
        if detail.contains("tcpShutdown") {
            return "SSH connection closed unexpectedly. Wait 5 seconds before reconnecting. (\(detail))"
        }
        if detail.contains("creatingChannelAfterClosure") {
            return "SSH session ended before the tunnel finished starting. (\(detail))"
        }
        if detail.contains("connectTimeout") || detail.contains("ChannelError") {
            return """
            SSH login timed out — the phone could not finish the SSH handshake in time. \
            Check network reachability to the entry hop, then retry. (\(detail))
            """
        }
        if error.code == 1 {
            return """
            SSH failed during tunnel setup (NIOSSH 1). \
            Ensure hopperd is running (hopperctl start). \
            Wait 5 seconds before reconnecting. (\(detail))
            """
        }
        return "SSH tunnel failed (NIOSSH \(error.code)). Check server auth.log and hopperd."
    }

    private static func friendlySSHByteStreamError(_ error: Error) -> String? {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty,
           String(describing: error).contains("SSHByteStreamError") {
            return description
        }
        let rendered = String(describing: error)
        guard rendered.contains("SSHByteStreamError") else { return nil }
        if rendered.contains("closed") {
            return """
            SSH tunnel stream closed — hopperd ended the session. On the entry server run: \
            tail -30 ~/.hopper/hopper.log
            """
        }
        return "SSH tunnel stream error. Check ~/.hopper/hopper.log on the server."
    }

    private static func friendlyIPTunnelProtocolError(_ error: Error) -> String? {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty,
           String(describing: error).contains("IPTunnelProtocolError") {
            return description
        }

        let ns = error as NSError
        if ns.domain.contains("IPTunnelProtocolError") {
            switch ns.code {
            case 0:
                return IPTunnelProtocolError.truncated.errorDescription
            case 1:
                return IPTunnelProtocolError.badVersion.errorDescription
            case 2:
                return IPTunnelProtocolError.badType.errorDescription
            case 3:
                return IPTunnelProtocolError.packetTooLarge.errorDescription
            default:
                break
            }
        }

        let rendered = String(describing: error)
        guard rendered.contains("IPTunnelProtocolError") else { return nil }
        if rendered.contains("badVersion") {
            return IPTunnelProtocolError.badVersion.errorDescription
        }
        if rendered.contains("assignFailed") {
            return rendered
        }
        return "IPTunnel protocol error during VPN setup. Try Connect with restart hopperd."
    }

    private static func friendlyHopperExtensionError(_ ns: NSError, error: Error) -> String? {
        let domain = ns.domain
        guard domain.contains("HopperExtension") || domain.contains(HopConstants.mainBundleID) else {
            return nil
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        if !ns.localizedDescription.isEmpty, ns.localizedDescription != "(null)" {
            return ns.localizedDescription
        }

        return "Tunnel extension error (\(domain) code \(ns.code)). Rebuild the app and verify hopperd is running."
    }

    private static func describeText(_ rendered: String, fallback: String) -> String {
        if !rendered.isEmpty, rendered != String(reflecting: rendered) {
            return rendered
        }
        return fallback.isEmpty ? rendered : fallback
    }
}
