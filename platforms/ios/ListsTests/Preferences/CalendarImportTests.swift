import Foundation
import Testing
@testable import Lists

struct CalendarImportTests {
    private func source() -> CalendarImport.Values {
        .init(title: "Wash the Dog", body: "Original notes", start: Date(timeIntervalSince1970: 1000),
              end: Date(timeIntervalSince1970: 4600), allDay: false, timeZone: "UTC")
    }
    private func imported() -> Item {
        let values = source()
        var item = Item(type: .event, title: values.title, listId: "personal", due: values.start,
                        dueTimeZone: values.timeZone, end: values.end)
        item.body = values.body
        item.calendarImport = CalendarImport(connectionID: UUID(), sourceKey: "stable", localIdentifier: "local",
                                              calendarName: "Personal", baseline: values, checkedAt: .now)
        return item
    }
    @Test func untouchedFieldsUpdateWithoutChangingIdentityOrDestination() {
        var item = imported(); item.listId = "home"
        var source = source(); source.title = "Wash Penny"; source.start += 3600; source.end += 3600
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.id == item.id)
        #expect(result.listId == "home")
        #expect(result.title == source.title)
        #expect(result.due == source.start)
        #expect(result.calendarImport?.conflicts.isEmpty == true)
    }
    @Test func localTitleAndTypeSurviveSourceChangesAndAcknowledgement() {
        var item = imported(); item.title = "Wash the Dog Penny"; item.type = .task; item.end = nil
        var source = source(); source.title = "Wash the Dog Saturday"; source.start += 3600; source.end += 3600
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.title == item.title)
        #expect(result.type == .task)
        #expect(result.end == nil)
        #expect(result.due == source.start)
        #expect(result.calendarImport?.conflicts == [.title])
        let kept = CalendarImport.resolve(.title, useSource: false, item: result)
        #expect(CalendarImport.merge(source, into: kept, now: .now).calendarImport?.conflicts.isEmpty == true)
        let accepted = CalendarImport.resolve(.title, useSource: true, item: result)
        #expect(accepted.title == source.title)
    }
    @Test func localScheduleConflictsAndDetachedItemsDoNotChange() {
        var item = imported(); item.due = Date(timeIntervalSince1970: 9999)
        var source = source(); source.start += 100; source.end += 100
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.due == item.due)
        #expect(result.calendarImport?.conflicts == [.schedule])
        item.calendarImport?.detached = true
        #expect(CalendarImport.merge(source, into: item, now: .now) == item)
    }
    @Test func metadataRoundTrips() throws {
        let item = imported()
        let decoded = try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(item))
        #expect(decoded.calendarImport == item.calendarImport)
        let markdown = try FrontmatterCodec.encode(item)
        let reopened = try FrontmatterCodec.decode(markdown)
        #expect(reopened.calendarImport?.sourceKey == item.calendarImport?.sourceKey)
        #expect(reopened.calendarImport?.baseline == item.calendarImport?.baseline)
    }
}
