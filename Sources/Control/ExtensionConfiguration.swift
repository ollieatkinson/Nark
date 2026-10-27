import Firewall
import Foundation

@objc public protocol FirewallService {

    func request(_ payload: Data, reply: @escaping (Data) -> Void)
}

public enum ExtensionConfiguration {

    public static let appID = "com.ollieatkinson.Nark"
    public static let extensionID = appID + ".Filter"
    public static func serviceName(bundle: Bundle = .main) -> String? {
        if let network = bundle.infoDictionary?["NetworkExtension"] as? [String: Any],
           let name = network["NEMachServiceName"] as? String {
            return name
        }
        return bundle.object(forInfoDictionaryKey: "NarkMachService") as? String
    }
}
