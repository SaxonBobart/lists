import SwiftUI
import Testing
import UIKit
@testable import Lists

@MainActor
struct QuickCaptureSheetRenderTests {
    private func host(_ view: some View) {
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let controller = UIHostingController(rootView: view.frame(width: 393, height: 852))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
        if let window {
            window.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        #expect(controller.view != nil, "the quick capture view must build and lay out without crashing")
        window?.isHidden = true
        window?.rootViewController = nil
    }

    @Test func quickCaptureSheetRenders() async throws {
        let store = try await TestStore.seeded()

        host(QuickCaptureSheet(store: store, defaultListId: ItemList.inboxId))
    }

    @Test func quickCaptureSheetRendersWithAppWideHabitDefault() async throws {
        let store = try await TestStore.seeded()

        host(
            QuickCaptureSheet(
                store: store,
                defaultListId: ItemList.inboxId,
                defaultNewItemType: .habit
            )
        )
    }

    @Test func extractedQuickCaptureSectionsRender() {
        host(QuickCaptureScheduleHarness())
    }
}

private struct QuickCaptureScheduleHarness: View {
    @State private var type: Item.ItemType = .task
    @State private var due = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var allDay = false
    @State private var hasDate = true
    @State private var hasTime = true
    @State private var hasReminder = true
    @State private var hasAlarm = false
    @State private var repeatPreset: RepeatPreset = .daily
    @State private var endRepeatOn = true
    @State private var endRepeatDate = Date().addingTimeInterval(86_400)
    @State private var earlyPreset: EarlyReminderPreset = .fifteenMin

    var body: some View {
        Form {
            QuickCaptureDateAndTimeSection(
                selectedType: type,
                due: $due,
                endDate: $endDate,
                allDay: $allDay,
                hasDate: $hasDate,
                hasTime: $hasTime,
                hasReminder: $hasReminder,
                hasAlarm: $hasAlarm,
                datePickerExpanded: true,
                timePickerExpanded: true,
                dateSubtitle: "Today",
                timeSubtitle: "9:00 AM",
                timeZoneLabel: "Current",
                onToggleDatePicker: {},
                onToggleTimePicker: {},
                onShowTimeZonePicker: {}
            )

            QuickCaptureRepeatAndEarlySection(
                repeatPresets: RepeatPreset.taskOptions,
                repeatPreset: $repeatPreset,
                repeatDisplay: "Daily",
                endRepeatOn: $endRepeatOn,
                endRepeatDate: $endRepeatDate,
                endRepeatSubtitle: "Tomorrow",
                hasReminder: hasReminder,
                earlyPreset: $earlyPreset,
                earlyDisplay: "15 minutes before",
                onShowRepeatCustom: {},
                onShowEarlyCustom: {}
            )
        }
    }
}
