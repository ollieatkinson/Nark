import Foundation

extension Firewall {

    public enum Error: Swift.Error, LocalizedError, Sendable {
        case message(String)
        public var errorDescription: String? {
            if case .message(let text) = self {
                text
            } else {
                "Nark error"
            }
        }
    }
}
