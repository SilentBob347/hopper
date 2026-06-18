import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject private var vpn: VPNController
    let serverID: UUID

    @State private var name: String = ""
    @State private var showExport = false

    private var server: HopNodeProfile? {
        vpn.state.server(id: serverID)
    }

    var body: some View {
        Group {
            if let server {
                Form {
                    Section("Name") {
                        TextField("Server name", text: $name)
                            .onChange(of: name) { _, newValue in
                                vpn.renameServer(id: serverID, name: newValue)
                            }
                    }

                    Section("Connection") {
                        LabeledContent("Host", value: server.trimmedHost)
                        LabeledContent("Port", value: String(server.port))
                        LabeledContent("User", value: server.trimmedUser)
                        if !server.installDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            LabeledContent("Install path", value: server.installDir)
                        }
                    }

                    Section("Share") {
                        Button("Export…") { showExport = true }
                    }
                }
            } else {
                ContentUnavailableView("Server not found", systemImage: "server.rack")
            }
        }
        .navigationTitle(server?.displayName ?? "Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = server?.name ?? ""
        }
        .sheet(isPresented: $showExport) {
            if let server {
                ServerExportView(server: server)
            }
        }
    }
}
