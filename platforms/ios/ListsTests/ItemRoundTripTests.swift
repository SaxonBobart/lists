import Foundation
import Testing
@testable import Lists

@Suite("Item round-trip")
struct ItemRoundTripTests {

    @Test("Task encodes + decodes losslessly")
    func taskRoundTrip() throws {
        let original = Item(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            type: .task,
            title: "Pay phone bill",
            body: "Due before close of business.\n",
            listId: "inbox",
            tags: ["finance", "monthly"],
            createdAt: Date(timeIntervalSince1970: 1_715_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_715_000_500),
            due: Date(timeIntervalSince1970: 1_715_700_000),
            priority: .medium,
            flagged: true
        )

        let serialized = try FrontmatterCodec.encode(original)
        let decoded = try FrontmatterCodec.decode(serialized)

        #expect(decoded.id == original.id)
        #expect(decoded.type == .task)
        #expect(decoded.title == original.title)
        #expect(decoded.body == original.body)
        #expect(decoded.listId == original.listId)
        #expect(decoded.tags == original.tags)
        #expect(decoded.due == original.due)
        #expect(decoded.priority == .medium)
        #expect(decoded.flagged == true)
    }

    @Test("Note has no done/priority frontmatter when defaulted")
    func noteRoundTrip() throws {
        let note = Item(
            type: .note,
            title: "Meeting transcript",
            body: "## Attendees\n\n- Alice\n- Bob\n",
            listId: "inbox"
        )

        let serialized = try FrontmatterCodec.encode(note)
        #expect(!serialized.contains("done:"))
        #expect(!serialized.contains("flagged:"))
        #expect(!serialized.contains("priority:"))
        #expect(serialized.contains("type: note"))
        #expect(serialized.contains("## Attendees"))

        let decoded = try FrontmatterCodec.decode(serialized)
        #expect(decoded.type == .note)
        #expect(decoded.body == note.body)
    }

    @Test("Habit emits frequency + completion log")
    func habitRoundTrip() throws {
        let habit = Item(
            type: .habit,
            title: "Meditate",
            body: "",
            listId: "inbox",
            frequency: .daily,
            goalPerCycle: 1,
            completionLog: ["2026-05-08": 1, "2026-05-09": 1],
            showStreak: true
        )

        let serialized = try FrontmatterCodec.encode(habit)
        let decoded = try FrontmatterCodec.decode(serialized)

        #expect(decoded.type == .habit)
        #expect(decoded.frequency == .daily)
        #expect(decoded.goalPerCycle == 1)
        #expect(decoded.completionLog == ["2026-05-08": 1, "2026-05-09": 1])
        #expect(decoded.showStreak == true)
    }

    @Test("Frontmatter delimiters are exact")
    func framingShape() throws {
        let item = Item(type: .task, title: "X", listId: "inbox")
        let serialized = try FrontmatterCodec.encode(item)
        #expect(serialized.hasPrefix("---\n"))
        #expect(serialized.contains("\n---\n"))
    }

    @Test("Decode rejects missing opener")
    func rejectsMissingOpener() {
        #expect(throws: FrontmatterCodec.Error.missingOpener) {
            _ = try FrontmatterCodec.decode("title: oops\n")
        }
    }
}
