import SwiftTUI

extension UI {

    /// One column contract for both collection headings and their rows.
    public struct ColumnLayout: Sendable {

        let middle: Int?
        let trailing: Int
        var middleLeading = false
        public static let application = Self(middle: 6, trailing: 6)
        public static let connection = Self(middle: 7, trailing: 6)
        public static let community = Self(middle: 26, trailing: 7, middleLeading: true)
        public static let rule = Self(middle: nil, trailing: 6)
    }

    public struct Columns<Leading: View, Middle: View, Trailing: View>: View {

        private let layout: ColumnLayout
        private let isHeader: Bool
        private let showsMiddle: Bool
        private let leading: Leading
        private let middle: Middle
        private let trailing: Trailing

        public init(
            _ layout: ColumnLayout,
            isHeader: Bool = false,
            showsMiddle: Bool = true,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder middle: () -> Middle,
            @ViewBuilder trailing: () -> Trailing
        ) {
            self.layout = layout
            self.isHeader = isHeader
            self.showsMiddle = showsMiddle
            self.leading = leading()
            self.middle = middle()
            self.trailing = trailing()
        }

        public var body: some View {
            HStack(spacing: 1) {
                leading
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if !showsMiddle {
                    EmptyView()
                } else if let width = layout.middle {
                    middle
                        .frame(
                            width: width,
                            alignment: layout.middleLeading ? .leading : .trailing
                        )
                        .lineLimit(1)
                } else {
                    middle
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
                trailing
                    .frame(width: layout.trailing, alignment: .trailing)
                    .lineLimit(1)
            }

            // SwiftTUI.List reserves two cells for its selection marker. Headings
            // sit outside the list and must reserve the same space.
            .padding(.leading, isHeader ? 2 : 0)
        }
    }
}
