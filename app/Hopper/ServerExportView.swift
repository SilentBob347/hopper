import CoreImage.CIFilterBuiltins
import SwiftUI

struct ServerExportView: View {
    let server: HopNodeProfile
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var errorMessage: String?

    private var qrJSON: String {
        (try? HopperConf.qrPayloadJSON(for: .server(server))) ?? "{}"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scan on another device to import this server. The QR is only for in-person transfer — it is not shared as a file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let qr = HopQRCodeImage.make(from: qrJSON) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    } else {
                        Text("Could not generate QR code.")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("QR (device to device)")
                }

                Section {
                    SecureField("Optional encryption password", text: $password)
                    Text("Leave empty to use the default password. The file always encrypts private keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Share .hopperconf…") {
                        shareFile()
                    }
                } header: {
                    Text("Share file")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func shareFile() {
        errorMessage = nil
        do {
            let data = try HopperConf.encryptFile(payload: .server(server), password: password)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(HopperConf.suggestedFileName(for: .server(server)))
            try data.write(to: url, options: .atomic)
            HopperConfSharePresenter.present(fileURL: url) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum HopQRCodeImage {
    static func make(from string: String, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
