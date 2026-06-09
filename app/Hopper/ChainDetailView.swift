import SwiftUI

struct ChainDetailView: View {
    @EnvironmentObject private var vpn: VPNController
    let chainID: UUID

    @State private var name: String = ""
    @State private var showAddServer = false

    private var chain: HopChain? {
        vpn.state.chains.first { $0.id == chainID }
    }

    private var hops: [HopNodeProfile] {
        guard let chain else { return [] }
        return vpn.state.resolveHops(chain)
    }

    var body: some View {
        Group {
            if chain != nil {
                Form {
                    Section("Name") {
                        TextField("Chain name", text: $name)
                            .onChange(of: name) { _, newValue in
                                vpn.renameChain(id: chainID, name: newValue)
                            }
                    }

                    Section("Route (entry → exit)") {
                        if hops.isEmpty {
                            Text("Add servers from your library.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(roleLabel(index: index, total: hops.count, hop: hop))
                                        .font(.headline)
                                    Text("\(hop.trimmedUser)@\(hop.trimmedHost):\(hop.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onDelete { offsets in
                                vpn.removeHopFromChain(chainID: chainID, at: offsets)
                            }
                            .onMove { source, destination in
                                vpn.moveHopInChain(chainID: chainID, from: source, to: destination)
                            }
                        }

                        Button("Add server…") { showAddServer = true }
                            .disabled(availableServers.isEmpty)
                    }
                }
            } else {
                ContentUnavailableView("Chain not found", systemImage: "link.badge.plus")
            }
        }
        .navigationTitle(chain?.displayName ?? "Chain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hops.isEmpty {
                EditButton()
            }
        }
        .onAppear {
            name = chain?.name ?? ""
        }
        .sheet(isPresented: $showAddServer) {
            NavigationStack {
                List(availableServers) { server in
                    Button {
                        vpn.addServerToChain(chainID: chainID, serverID: server.id)
                        showAddServer = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.displayName).font(.headline)
                            Text("\(server.trimmedUser)@\(server.trimmedHost):\(server.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .navigationTitle("Add server")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddServer = false }
                    }
                }
            }
        }
    }

    private var availableServers: [HopNodeProfile] {
        guard let chain else { return vpn.state.servers }
        let used = Set(chain.hopIDs)
        return vpn.state.servers.filter { !used.contains($0.id) }
    }

    private func roleLabel(index: Int, total: Int, hop: HopNodeProfile) -> String {
        let role: String
        if total == 1 {
            role = "Exit"
        } else if index == 0 {
            role = "Entry"
        } else if index == total - 1 {
            role = "Exit"
        } else {
            role = "Relay"
        }
        return "\(index + 1). \(role) — \(hop.displayName)"
    }
}
