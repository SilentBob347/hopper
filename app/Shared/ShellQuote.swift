import Foundation

enum ShellQuote {
    static func bashSingle(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
