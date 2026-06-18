import CoreImage.CIFilterBuiltins
import SwiftUI

struct ServerExportView: View {
    let server: HopNodeProfile
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var configJSON: String {
        HopQRExporter.exportJSON(server)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Scan on another device to import this server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if let qr = HopQRCodeImage.make(from: configJSON) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                } else {
                    Text("Could not generate QR code.")
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                Button(copied ? "Copied" : "Copy config") {
                    UIPasteboard.general.string = configJSON
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
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
}

private enum HopQRCodeImage {
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
