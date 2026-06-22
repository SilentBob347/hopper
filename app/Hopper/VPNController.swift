import Foundation
import NetworkExtension

struct ServerUpdatePrompt: Identifiable, Equatable {
    let id = UUID()
    let hops: [HopNodeProfile]
    let targetVersion: String
}

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var vpnStatus: NEVPNStatus = .invalid
    @Published private(set) var provisionStatus: String?
    @Published var errorMessage: String?
    @Published var serverUpdatePrompt: ServerUpdatePrompt?
    @Published private(set) var chainStatusReports: [UUID: [ChainStatusReport]] = [:]

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var pendingConnectRestart = false

    init() {
        state = ProfileStore.load()
        Task { await reloadVPN() }
    }

    var isConnected: Bool { vpnStatus == .connected }
    var isBusy: Bool { vpnStatus == .connecting || vpnStatus == .disconnecting }

    // MARK: - Servers

    func addServer(_ server: HopNodeProfile) {
        state.addServer(server)
        persist()
    }

    func addDeployKey(_ key: DeploySSHKey) {
        state.addDeployKey(key)
        persist()
    }

    func deployServer(
        host: String,
        port: Int,
        user: String,
        auth: ServerDeployAuth,
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let result = try await ServerDeployer.deploy(
            host: host,
            port: port,
            user: user,
            auth: auth,
            onLog: onLog
        )
        if let newKey = result.newDeployKey {
            state.addDeployKey(newKey)
        }
        state.addServer(result.profile)
        persist()
    }

    func deleteServers(at offsets: IndexSet) {
        state.removeServers(at: offsets)
        persist()
    }

    func renameServer(id: UUID, name: String) {
        state.renameServer(id: id, name: name)
        persist()
    }

    // MARK: - Chains

    @discardableResult
    func addChain(name: String = "") -> UUID {
        let id = state.addChain(name: name)
        persist()
        return id
    }

    func deleteChains(at offsets: IndexSet) {
        state.removeChains(at: offsets)
        persist()
    }

    func selectChain(_ id: UUID?) {
        state.selectChain(id)
        persist()
    }

    func renameChain(id: UUID, name: String) {
        state.renameChain(id: id, name: name)
        persist()
    }

    func moveHopInChain(chainID: UUID, from source: IndexSet, to destination: Int) {
        state.moveHopInChain(chainID: chainID, from: source, to: destination)
        persist()
    }

    func addServerToChain(chainID: UUID, serverID: UUID) {
        state.addServerToChain(chainID: chainID, serverID: serverID)
        persist()
    }

    func removeHopFromChain(chainID: UUID, at offsets: IndexSet) {
        state.removeHopFromChain(chainID: chainID, at: offsets)
        persist()
    }

    // MARK: - Status

    func fetchChainStatus(chainID: UUID) async {
        guard let chain = state.chains.first(where: { $0.id == chainID }) else { return }
        let hops = state.resolveHops(chain)
        var reports: [ChainStatusReport] = []
        await withTaskGroup(of: ChainStatusReport?.self) { group in
            for hop in hops {
                group.addTask {
                    try? await ChainStatusService.fetch(on: hop, chainID: chainID)
                }
            }
            for await report in group {
                if let report { reports.append(report) }
            }
        }
        chainStatusReports[chainID] = reports
    }

    // MARK: - VPN

    func connect(restartHopperd: Bool = false) async {
        guard let chain = state.selectedChain, let entry = state.entryHop else {
            reportError("Select a chain with at least one server (entry → exit).")
            return
        }
        errorMessage = nil
        provisionStatus = nil
        ProfileStore.clearLastTunnelError()

        let hops = state.activeHops
        do {
            provisionStatus = "Checking server versions…"
            let versionOutcome = try await preflightVersions(hops: hops)
            switch versionOutcome {
            case .appTooOld(let required):
                provisionStatus = nil
                reportError("App version \(HopVersion.appVersion) is too old. Update to \(required) or newer.")
                return
            case .serverTooOld(let outdated):
                provisionStatus = nil
                serverUpdatePrompt = ServerUpdatePrompt(
                    hops: outdated,
                    targetVersion: HopVersion.manifest.version
                )
                pendingConnectRestart = restartHopperd
                return
            case .compatible:
                break
            }

            try await performConnect(chain: chain, entry: entry, hops: hops, restartHopperd: restartHopperd)
        } catch {
            provisionStatus = nil
            reportError(HopErrorDetails.describe(error))
        }
    }

    func confirmServerUpdate() async {
        guard let prompt = serverUpdatePrompt else { return }
        serverUpdatePrompt = nil
        errorMessage = nil
        provisionStatus = "Updating servers…"
        do {
            for hop in prompt.hops {
                try await VersionService.updateServer(on: hop, to: prompt.targetVersion)
            }
            guard let chain = state.selectedChain, let entry = state.entryHop else { return }
            try await performConnect(
                chain: chain,
                entry: entry,
                hops: state.activeHops,
                restartHopperd: pendingConnectRestart
            )
        } catch {
            provisionStatus = nil
            reportError(HopErrorDetails.describe(error))
        }
    }

    func cancelServerUpdate() {
        serverUpdatePrompt = nil
        pendingConnectRestart = false
    }

    private func performConnect(
        chain: HopChain,
        entry: HopNodeProfile,
        hops: [HopNodeProfile],
        restartHopperd: Bool
    ) async throws {
        provisionStatus = "Provisioning chain (exit → entry)…"
        _ = try await ChainProvisioner.provision(
            chainID: chain.id,
            chain: hops,
            restartHopperd: restartHopperd
        ) { [weak self] index, total, message in
            Task { @MainActor in
                self?.provisionStatus = "[\(total - index)/\(total)] \(message)"
            }
        }
        provisionStatus = "Starting VPN…"

        let context = TunnelConnectContext(
            chainID: chain.id,
            hopperPort: ChainTopology.listenPort(chainID: chain.id),
            overlayCIDR: ChainTopology.overlayCIDR(chainID: chain.id),
            deviceID: ProfileStore.deviceID()
        )

        let manager = try await ensureManager(hop: entry, context: context)
        self.manager = manager
        observeStatus()
        try manager.connection.startVPNTunnel(options: TunnelBootstrap.options(hop: entry, context: context))
        provisionStatus = nil
    }

    private enum PreflightResult {
        case compatible
        case appTooOld(required: String)
        case serverTooOld(hops: [HopNodeProfile])
    }

    private func preflightVersions(hops: [HopNodeProfile]) async throws -> PreflightResult {
        var infos: [(hop: HopNodeProfile, info: ServerVersionInfo)] = []
        try await withThrowingTaskGroup(of: (HopNodeProfile, ServerVersionInfo).self) { group in
            for hop in hops {
                group.addTask {
                    let info = try await VersionService.fetchServerVersion(on: hop)
                    return (hop, info)
                }
            }
            for try await pair in group {
                infos.append((hop: pair.0, info: pair.1))
            }
        }

        for item in infos {
            if let minApp = item.info.minAppVersion,
               SemVer.compare(HopVersion.appVersion, minApp) == .orderedAscending {
                return .appTooOld(required: minApp)
            }
        }

        var outdated: [HopNodeProfile] = []
        for item in infos {
            guard let serverVersion = item.info.version else {
                outdated.append(item.hop)
                continue
            }
            if SemVer.compare(serverVersion, HopVersion.manifest.minServerVersion) == .orderedAscending {
                continue
            }
            outdated.append(item.hop)
        }

        if !outdated.isEmpty {
            return .serverTooOld(hops: outdated)
        }
        return .compatible
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func toggle(restartHopperd: Bool = false) async {
        if isConnected || isBusy {
            disconnect()
        } else {
            await connect(restartHopperd: restartHopperd)
        }
    }

    private func persist() {
        ProfileStore.save(state)
    }

    private func ensureManager(hop: HopNodeProfile, context: TunnelConnectContext) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first(where: Self.isHopperManager) ?? NETunnelProviderManager()

        manager.localizedDescription = HopConstants.appDisplayName
        manager.isEnabled = true
        manager.protocolConfiguration = Self.makeProtocol(hop: hop, context: context)

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        guard manager.protocolConfiguration is NETunnelProviderProtocol else {
            throw VPNError.invalidProtocol
        }

        vpnStatus = manager.connection.status
        return manager
    }

    private func reloadVPN() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first(where: Self.isHopperManager)
            vpnStatus = manager?.connection.status ?? .invalid
            observeStatus()
        } catch {
            reportError(HopErrorDetails.describe(error))
        }
    }

    private func observeStatus() {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        guard let connection = manager?.connection else { return }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.vpnStatus = self.manager?.connection.status ?? .invalid
                if self.vpnStatus == .disconnected {
                    await self.readTunnelError()
                }
            }
        }
    }

    private func readTunnelError() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let saved = ProfileStore.loadLastTunnelError() {
            reportError(saved)
            return
        }
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        session.fetchLastDisconnectError { [weak self] error in
            Task { @MainActor in
                guard let self, let error else { return }
                self.reportError(HopErrorDetails.describe(error))
            }
        }
    }

    private func reportError(_ message: String) {
        let detail = HopErrorDetails.describeMessage(message)
        errorMessage = detail
        TunnelLog.error("[App] \(detail)")
    }

    private static func isHopperManager(_ manager: NETunnelProviderManager) -> Bool {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerBundleIdentifier == HopConstants.tunnelBundleID
    }

    private static func makeProtocol(hop: HopNodeProfile, context: TunnelConnectContext) -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = HopConstants.tunnelBundleID
        proto.serverAddress = hop.trimmedHost
        proto.providerConfiguration = TunnelBootstrap.options(hop: hop, context: context)
        return proto
    }
}

enum VPNError: LocalizedError {
    case invalidProtocol

    var errorDescription: String? {
        switch self {
        case .invalidProtocol:
            return "VPN protocol configuration is invalid. Reinstall the app and try again."
        }
    }
}
