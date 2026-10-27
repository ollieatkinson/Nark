import Geography
import Testing

@Test func offline_lookup_handles_public_private_mapped_ipv6_and_invalid_addresses() async throws {
    let results = try await Database.locate([
        "8.8.8.8",
        "2001:4860:4860::8888",
        "192.168.1.2",
        "::1",
        "fe80::1%en0",
        "::ffff:192.168.1.2",
        "nonsense",
        "",
        "224.0.0.1"
    ])
    #expect(results["8.8.8.8"] == "US")
    #expect(results["2001:4860:4860::8888"] == "CA")
    for local in ["192.168.1.2", "::1", "fe80::1%en0", "::ffff:192.168.1.2"] {
        #expect(results[local] == "LOCAL")
    }
    #expect(results["nonsense"] == "ZZ")
    #expect(results[""] == "ZZ")
    #expect(results["224.0.0.1"] == "ZZ")
    #expect(World.bundled.country(x: 0, y: 0) == nil)
}

@Test func country_anchors_are_offline_country_points_and_local_addresses_have_no_geographic_point(
) throws {
    let point = try #require(World.countryPoints["GB"])
    #expect((-10 ... 5).contains(point.longitude))
    #expect((49 ... 61).contains(point.latitude))
    #expect(World.countryPoints["LOCAL"] == nil)
    #expect(World.countryPoints["ZZ"] == nil)
}
