import Testing

@Suite("Sanity")
struct SanityTests {
    @Test func toolingIsWiredUp() {
        #expect(1 + 1 == 2)
    }
}
