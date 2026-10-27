import SwiftTUI

extension UI {

    public struct DenseListStyle: ListStyle, Sendable {

        public init() {}

        public var snapshotLabel: String {
            "ListStyle.dense"
        }

        public func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
            .init(showsRowSeparators: false, showsSectionSeparators: false)
        }
    }
}
