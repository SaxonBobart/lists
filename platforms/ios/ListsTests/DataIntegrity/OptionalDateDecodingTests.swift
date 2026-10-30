import Foundation
import Testing
@testable import Lists

/// An optional date that is *present but unparseable* must fail safe.
/// Previously a garbage `deleted_at`/`due`/`completed_at` mapped to nil — which
/// silently dropped the value (and, for `deleted_at`, resurrected a deleted
/// item). Now it throws, so per-file quarantine catches the file and the item
/// stays out of the live set. An *absent* optional date still means nil.
struct OptionalDateDecodingTests {

    /// Valid item frontmatter (with due/completed_at/deleted_at all set), then
    /// the named date field's value replaced with garbage.
    private func itemFrontmatter(corrupting key: String) throws -> String {
        var item = Item(type: .task, title: "X", listId: "l1")
        item.due = .now
        item.completedAt = .now
        item.deletedAt = .now
        let encoded = try FrontmatterCodec.encode(item)
        return encoded.replacingOccurrences(
            of: "(?m)^\(key): .*$", with: "\(key): not-a-real-date",
            options: .regularExpression)
    }

    @Test func garbageDueThrows() throws {
        try expectDecodeThrows(itemFrontmatter(corrupting: "due"))
    }

    @Test func garbageCompletedAtThrows() throws {
        try expectDecodeThrows(itemFrontmatter(corrupting: "completed_at"))
    }

    @Test func garbageDeletedAtThrows() throws {
        try expectDecodeThrows(itemFrontmatter(corrupting: "deleted_at"))
    }

    @Test func absentOptionalDatesStillDecodeAsNil() throws {
        // A plain item has no due/completed_at/deleted_at — absence is fine.
        let item = try FrontmatterCodec.decode(
            FrontmatterCodec.encode(Item(type: .task, title: "X", listId: "l1")))
        #expect(item.due == nil)
        #expect(item.completedAt == nil)
        #expect(item.deletedAt == nil)
    }

    /// A list whose `deleted_at` is corrupt on disk is quarantined rather than
    /// silently resurrected into the live set.
    @Test func listWithGarbageDeletedAtIsQuarantined() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsDI3-\(UUID().uuidString)")
        let store = FileStore(root: root)
        try await store.ensureRoot()
        try await store.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0,
                                           deletedAt: .now))
        let listFile = try await store.listDirectory(for: "l1").appendingPathComponent(".list.yml")
        let corrupted = try String(contentsOf: listFile, encoding: .utf8)
            .replacingOccurrences(of: "(?m)^deleted_at: .*$",
                                  with: "deleted_at: not-a-real-date",
                                  options: .regularExpression)
        try corrupted.write(to: listFile, atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        #expect(result.quarantined.count == 1)
        #expect(!result.lists.contains { $0.list.id == "l1" })
    }

    // MARK: - All-day dates are calendar days, not instants

    @Test func allDayDueEncodesAsDayStringAndRoundTripsTheSameDay() throws {
        var item = Item(type: .task, title: "Birthday", listId: "l1")
        let due = Calendar.current.startOfDay(for: .now)
        item.dueAllDay = true
        item.due = due

        let encoded = try FrontmatterCodec.encode(item)
        let dayString = ISO8601.localDayString(from: due)
        let dueLine = try #require(encoded.split(separator: "\n").first { $0.hasPrefix("due:") }.map(String.init))
        #expect(dueLine.contains(dayString),
                "an all-day due is written as a bare yyyy-MM-dd day")
        #expect(!dueLine.contains("T"),
                "no timestamp tail on the due line — day-only encoding is real now")

        let decoded = try FrontmatterCodec.decode(encoded)
        let decodedDue = try #require(decoded.due)
        #expect(Calendar.current.isDate(decodedDue, inSameDayAs: due),
                "reload lands on the same local calendar day — no off-by-one drift")
        #expect(decoded.dueAllDay)
    }

    @Test func timedDueStillRoundTripsAsAnExactInstant() throws {
        var item = Item(type: .task, title: "Call", listId: "l1")
        item.due = ISO8601.date(from: "2026-06-12T09:30:00.000Z")
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.due == item.due, "timed dues are exact instants, unchanged")
    }



    // MARK: - Body frontmatter separators survive the round-trip

    @Test func bodyWithHorizontalRuleRoundTrips() throws {
        var item = Item(type: .note, title: "Doc", listId: "l1")
        item.body = "intro\n\n---\n\noutro"
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        // The codec normalizes a trailing newline onto the body; tolerate that,
        // but any mis-split at the --- would still drop `outro` and fail here.
        #expect(decoded.body.trimmingCharacters(in: .newlines) == item.body,
                "a column-0 --- in the body must not be mistaken for the frontmatter closer")
    }

    private func expectDecodeThrows(_ document: String) throws {
        do {
            _ = try FrontmatterCodec.decode(document)
            Issue.record("Decode unexpectedly succeeded")
        } catch {
            return
        }
    }
}


struct CustomPropertyStorageTests {
    private func document(extra: String = "") throws -> String {
        let item = Item(type: .note, title: "Metadata", body: "Body kept\n", listId: "inbox")
        return try FrontmatterCodec.encode(item).replacingOccurrences(of: "\n---\nBody", with: "\n" + extra + "\n---\nBody")
    }

    @Test func legacyDocumentOmitsNewBlock() throws {
        let source = try document()
        let item = try FrontmatterCodec.decode(source)
        #expect(item.customProperties.isEmpty)
        #expect(!item.hasCustomPropertyStorageConflict)
        #expect(!(try FrontmatterCodec.encode(item)).contains("custom_properties:"))
    }

    @Test func customTextAndStableIdentityRoundTripWithoutChangingBody() throws {
        var item = try FrontmatterCodec.decode(document())
        let property = ItemCustomProperty(name: "Owner", value: "Saxon\nText: \"true\"")
        item.customProperties = [property]
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.customProperties == [property])
        #expect(decoded.body == item.body)
    }

    @Test func unrelatedAndNestedUnknownMetadataSurvivesKnownFieldEdit() throws {
        var item = try FrontmatterCodec.decode(document(extra: "future_field: {enabled: true, code: \"001\", nested: [1, \"2\", null]}\nvendor: {color: purple}"))
        let preserved = item.frontmatterExtensions
        item.flagged = true
        item.customProperties = [ItemCustomProperty(name: "Status", value: "Draft")]
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.frontmatterExtensions == preserved)
        #expect(decoded.flagged)
        #expect(decoded.body == item.body)
    }

    @Test func unsupportedCustomBlockIsKeptInsteadOfOverwritten() throws {
        let item = try FrontmatterCodec.decode(document(extra: "custom_properties: {future_schema: [one, two]}"))
        #expect(item.hasCustomPropertyStorageConflict)
        #expect(item.customProperties.isEmpty)
        var edited = item
        edited.priority = .high
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(edited))
        #expect(decoded.hasCustomPropertyStorageConflict)
        #expect(decoded.frontmatterExtensions == item.frontmatterExtensions)
        #expect(decoded.priority == .high)
    }

    @Test func futureAttributesOnCustomPropertySurviveEditingItsValue() throws {
        let id = UUID()
        var item = try FrontmatterCodec.decode(document(extra: "custom_properties:\n- id: \(id.uuidString)\n  name: Owner\n  value: Saxon\n  future_color: purple"))
        item.customProperties[0].value = "Updated"
        let encoded = try FrontmatterCodec.encode(item)
        let decoded = try FrontmatterCodec.decode(encoded)
        #expect(encoded.contains("future_color: purple"))
        #expect(decoded.customProperties[0].id == id)
        #expect(decoded.customProperties[0].value == "Updated")
    }

    @Test func removingARecognizedPropertyDoesNotResurrectItsFutureAttributes() throws {
        let id = UUID()
        var item = try FrontmatterCodec.decode(document(extra: "custom_properties:\n- id: \(id.uuidString)\n  name: Owner\n  value: Saxon\n  future_color: purple\nvendor: keep"))
        item.customProperties.removeAll()
        let encoded = try FrontmatterCodec.encode(item)
        #expect(!encoded.contains("custom_properties:"))
        #expect(try FrontmatterCodec.decode(encoded).frontmatterExtensions["vendor"] == item.frontmatterExtensions["vendor"])
    }

    @Test func duplicateIdentityIsAnUnsupportedBlockWithoutDataLoss() throws {
        let id = UUID()
        let item = try FrontmatterCodec.decode(document(extra: "custom_properties:\n- id: \(id.uuidString)\n  name: One\n  value: first\n- id: \(id.uuidString)\n  name: Two\n  value: second"))
        #expect(item.hasCustomPropertyStorageConflict)
        #expect(item.customProperties.isEmpty)
        #expect(try FrontmatterCodec.decode(FrontmatterCodec.encode(item)).frontmatterExtensions == item.frontmatterExtensions)
    }

    @Test func namesRejectBlankAndDuplicatesButAllowRenamingTheSameField() {
        let existing = ItemCustomProperty(name: "Owner")
        #expect(!ItemCustomProperty(name: "  ").hasValidName(among: []))
        #expect(!ItemCustomProperty(name: " owner ").hasValidName(among: [existing]))
        #expect(ItemCustomProperty(id: existing.id, name: "Owner").hasValidName(among: [existing]))
    }
}
