import AppKit
import Control
import Firewall
import Foundation
import NetworkExtension
import SystemExtensions

@MainActor
final class ExtensionControl: NSObject, OSSystemExtensionRequestDelegate {

    private var continuation: CheckedContinuation<Void, any Error>?

    enum Action {
        case activate
        case deactivate
        case disable
    }

    static func run(_ command: Action) async throws {
        guard Bundle.main.bundleIdentifier == ExtensionConfiguration.appID else {
            throw Firewall.Error.message("Activation requires the signed app bundle in /Applications.")
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let controller = ExtensionControl()
        if command == .activate {
            try await controller.submit(activate: true)
        }
        let manager = NEFilterManager.shared()
        try await manager.loadFromPreferences()
        if command == .activate {
            let configuration = NEFilterProviderConfiguration()
            configuration.filterSockets = true
            configuration.filterDataProviderBundleIdentifier = ExtensionConfiguration.extensionID
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Nark"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            print("Nark enabled. Approve the network filter in System Settings if prompted.")
        } else {
            manager.isEnabled = false
            try await manager.saveToPreferences()
            if command == .deactivate {
                try await controller.submit(activate: false)
            }
            print(command == .disable ? "Nark filtering disabled." : "Nark extension deactivated.")
        }
    }

    private func submit(activate: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = activate
                ? OSSystemExtensionRequest.activationRequest(
                    forExtensionWithIdentifier: ExtensionConfiguration.extensionID,
                    queue: .main
                )
                : OSSystemExtensionRequest.deactivationRequest(
                    forExtensionWithIdentifier: ExtensionConfiguration.extensionID,
                    queue: .main
                )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("Approve Nark in System Settings → General → Login Items & Extensions → Network Extensions.")
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            if result == .willCompleteAfterReboot {
                continuation?.resume(throwing: Firewall.Error.message("Restart macOS, then run activate again."))
            } else {
                continuation?.resume()
            }
            continuation = nil
        }
    }
}
