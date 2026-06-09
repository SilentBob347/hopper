import Foundation

struct HopReadyReport: Codable, Equatable {
    let ready: Bool
    let mode: String
    let addr: String
    let index: Int
    let overlay: String
    let port: Int
    let nat: Bool?

    static func parse(from output: String) throws -> HopReadyReport {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() where line.hasPrefix("{") {
            guard let data = line.data(using: .utf8) else { continue }
            if let report = try? JSONDecoder().decode(HopReadyReport.self, from: data), report.ready {
                return report
            }
        }
        throw ChainProvisionerError.invalidReadyJSON(output)
    }
}
