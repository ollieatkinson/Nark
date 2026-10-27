import Control
import Firewall

extension Firewall.Client {

    /// A deterministic transport confined to test targets.
    public init(runtime: Firewall.Runtime) {
        self.init(response: { runtime.handle($0) })
    }
}
