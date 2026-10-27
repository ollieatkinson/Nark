import Firewall
import Foundation
import Vocabulary

/// A versioned Lexicon event snapshot is the control protocol shared by both processes.
/// XPC provides request/reply correlation and authenticates the peer before decoding.
public struct Message: Codable, Sendable {

    public let version: Int
    public let event: Event.Snapshot

    public init(_ request: Firewall.Request) throws {
        let event: Event
        switch request {
            case .blocklist(let request):
                switch request {
                    case .replace(let input):
                        event = Event(try nark.policy.blocklist.replace.encoding(input))
                    case .toggle(let id):
                        event = Event(nark.policy.blocklist.toggle[id.uuidString])
                    case .remove(let id):
                        event = Event(nark.policy.blocklist.remove[id.uuidString])
                    case .read(let id):
                        event = Event(nark.policy.blocklist.read[id.uuidString])
                }
            case .recording(let request):
                switch request {
                    case .start(let application):
                        event = Event(try nark.activity.recording.start.encoding(application))
                    case .read(let cursor):
                        event = Event(try nark.activity.recording.read.encoding(cursor))
                    case .stop(let cursor):
                        event = Event(try nark.activity.recording.stop.encoding(cursor))
                    case .close(let id):
                        event = Event(nark.activity.recording.close[id.uuidString])
                }
            case .snapshot:
                event = Event(nark.activity.refresh)
            case .clearHistory:
                event = Event(nark.activity.clear)
            case .add(let rule):
                event = Event(try nark.policy.rule.add.encoding(rule))
            case .remove(let id):
                event = Event(nark.policy.rule.remove[id.uuidString])
            case .toggle(let id):
                event = Event(nark.policy.rule.toggle[id.uuidString])
            case .importDomains(let text):
                event = Event(nark.policy.rule.import[text])
        }
        version = 1
        self.event = event.snapshot
    }

    public func request() throws -> Firewall.Request {
        guard version == 1 else {
            throw Firewall.Error.message("Unsupported control protocol version: \(version)")
        }
        switch event.lemma {
            case nark.policy.blocklist.replace:
                return .blocklist(.replace(try value(at: nark.policy.blocklist.replace)))
            case nark.policy.blocklist.toggle:
                return .blocklist(.toggle(try identifier(at: nark.policy.blocklist.toggle)))
            case nark.policy.blocklist.remove:
                return .blocklist(.remove(try identifier(at: nark.policy.blocklist.remove)))
            case nark.policy.blocklist.read:
                return .blocklist(.read(try identifier(at: nark.policy.blocklist.read)))
            case nark.activity.recording.start:
                let application: Firewall.Application = try value(at: nark.activity.recording.start)
                return .recording(.start(try application.validated()))
            case nark.activity.recording.read:
                return .recording(.read(try value(at: nark.activity.recording.read)))
            case nark.activity.recording.stop:
                return .recording(.stop(try value(at: nark.activity.recording.stop)))
            case nark.activity.recording.close:
                return .recording(.close(try identifier(at: nark.activity.recording.close)))
            case nark.activity.refresh:
                return .snapshot
            case nark.activity.clear:
                return .clearHistory
            case nark.policy.rule.add:
                let rule: Firewall.Rule = try value(at: nark.policy.rule.add)
                return .add(try rule.validated())
            case nark.policy.rule.remove:
                return .remove(try identifier(at: nark.policy.rule.remove))
            case nark.policy.rule.toggle:
                return .toggle(try identifier(at: nark.policy.rule.toggle))
            case nark.policy.rule.import:
                return .importDomains(try value(at: nark.policy.rule.import))
            default:
                throw Firewall.Error.message("Unknown control message: \(event.lemma)")
        }
    }

    private func identifier(at path: some I) throws -> UUID {
        let raw: String = try value(at: path)
        guard let id = UUID(uuidString: raw) else {
            throw Firewall.Error.message("Invalid identifier.")
        }
        return id
    }

    private func value<Value: Decodable>(at path: some I) throws -> Value {
        guard let value = event.values[path.__] else {
            throw Firewall.Error.message("Missing value for \(path.__)")
        }
        return try value.value(as: Value.self)
    }
}
