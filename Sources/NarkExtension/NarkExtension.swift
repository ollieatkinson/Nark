import Foundation
import NetworkExtension

public enum NarkExtension {

    public static func main() -> Never {
        // Retain the provider metadata when the package is linked statically.
        precondition(NSClassFromString("FilterDataProvider") == FilterDataProvider.self)
        NEProvider.startSystemExtensionMode()
        dispatchMain()
    }
}
