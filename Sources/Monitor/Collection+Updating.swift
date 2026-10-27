/// Refresh values without using changing properties (such as enabled state) as
/// display order. Surviving IDs retain their positions; new IDs append in source order.
extension Array where Element: Identifiable {

    func updating(with incoming: Self) -> Self {
        var remaining = Dictionary(
            incoming.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        let retained = compactMap { remaining.removeValue(forKey: $0.id) }
        let added = incoming.compactMap { remaining.removeValue(forKey: $0.id) }
        return retained + added
    }
}
