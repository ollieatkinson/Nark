import Foundation

extension Firewall {

    public struct Response: Codable, Sendable {

        public var snapshot: Firewall.Snapshot?
        public var blocklist: Firewall.Blocklist?
        public var recording: Firewall.Recording.Batch?
        public var error: String?
        public init(
            snapshot: Firewall.Snapshot? = nil,
            recording: Firewall.Recording.Batch? = nil,
            error: String? = nil,
            blocklist: Firewall.Blocklist? = nil
        ) {
            self.snapshot = snapshot
            self.blocklist = blocklist
            self.recording = recording
            self.error = error
        }
    }
}
