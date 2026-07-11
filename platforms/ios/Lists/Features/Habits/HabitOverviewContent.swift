import Charts
import SwiftUI
import UIKit

/// Habit-specific presentation kept separate from the scheduler so the view's
/// status provider remains injectable in snapshots and focused tests.
enum HabitNotificationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case quiet
    case summarized
    case enabled

    static func current() async -> Self {
        let deliveryStatus = await NotificationScheduler.shared.deliveryStatus()
        switch deliveryStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .quiet:
            return .quiet
        case .summarized:
            return .summarized
        case .enabled:
            return .enabled
        }
    }

    var canDeliver: Bool {
        switch self {
        case .quiet, .summarized, .enabled: true
        case .notDetermined, .denied: false
        }
    }

    static func shouldRescheduleAfterRecovery(
        from previous: Self?,
        to current: Self
    ) -> Bool {
        guard let previous else { return false }
        return !previous.canDeliver && current.canDeliver
    }
}

struct HabitOverviewContent: View {
    let item: Item
    let store: ItemStore
    let now: Date
    let actionNow: @Sendable () -> Date
    let notificationStatusProvider: @Sendable () async -> HabitNotificationStatus
    let requestNotificationAuthorization: @Sendable () async -> Bool
    let rescheduleReminder: @Sendable (Item) async -> Void
    let onAddCompletion: (Date) -> Void
    let onEditCompletion: (HabitCompletion) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeOperation: CompletionOperation?
    @State private var operationFailure: CompletionFailure?
    @State private var notificationStatus: HabitNotificationStatus?
    @State private var awaitingNotificationSettingsReturn = false
    @State private var goalFeedback = 0

    private enum CompletionOperation: Equatable {
        case log
        case undo

        var failureTitle: String {
            switch self {
            case .log: "Couldn’t Log Completion"
            case .undo: "Couldn’t Undo Completion"
            }
        }
    }

    private struct CompletionFailure: Equatable {
        let operation: CompletionOperation
        let actionDate: Date
        let message: String
    }

    private struct ActivityPoint: Identifiable {
        let id: String
        let start: Date
        let count: Int
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ListsSpacing.s4) {
                header
                progressCard
                activityCard
                recentCard
                Spacer().frame(height: ListsSpacing.s8)
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
        .sensoryFeedback(.success, trigger: goalFeedback)
        .task(id: reminderTaskID) { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let forceReschedule = awaitingNotificationSettingsReturn
                    awaitingNotificationSettingsReturn = false
                    await refreshNotificationStatus(
                        forceRescheduleIfUsable: forceReschedule
                    )
                }
            }
        }
        .alert(
            operationFailure?.operation.failureTitle ?? "Couldn’t Update Habit",
            isPresented: isShowingOperationFailure
        ) {
            Button("Try Again") { retryFailedOperation() }
                .accessibilityIdentifier("habit.completion.error.retry")
            Button("Not Now", role: .cancel) {}
                .accessibilityIdentifier("habit.completion.error.dismiss")
        } message: {
            if let operationFailure { Text(operationFailure.message) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Text(item.title)
                .font(ListsTypography.largeTitle.bold())
                .foregroundStyle(ListsTokens.Foreground.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(habitSummary)
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            reminderRow
        }
    }

    @ViewBuilder
    private var reminderRow: some View {
        if hasReminder, let reminderTime = item.due {
            VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                Label {
                    Text(HabitReminderSchedule.summary(
                        frequency: cadence,
                        reminderTime: reminderTime,
                        timeZoneIdentifier: item.dueTimeZone
                    ))
                } icon: {
                    Image(systemName: "bell")
                }
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.secondary)

                notificationRecoveryControl
            }
        } else {
            Label("No reminder", systemImage: "bell.slash")
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
    }

    @ViewBuilder
    private var notificationRecoveryControl: some View {
        switch notificationStatus {
        case .notDetermined:
            Button("Allow Notifications") {
                Task {
                    let granted = await requestNotificationAuthorization()
                    if granted, hasReminder {
                        await rescheduleReminder(item)
                    }
                    await refreshNotificationStatus(rescheduleOnRecovery: false)
                }
            }
            .font(ListsTypography.footnote)
            .frame(minHeight: 44)
            .accessibilityIdentifier("habit.notifications.allow")
        case .denied:
            Button(action: openNotificationSettings) {
                Label("Notifications Off — Open Settings", systemImage: "exclamationmark.triangle")
            }
            .font(ListsTypography.footnote)
            .foregroundStyle(ListsTokens.Semantic.warning)
            .frame(minHeight: 44)
            .accessibilityIdentifier("habit.notifications.settings")
        case .quiet:
            Button(action: openNotificationSettings) {
                Label("Delivered Quietly — Open Settings", systemImage: "speaker.slash")
            }
            .font(ListsTypography.footnote)
            .foregroundStyle(ListsTokens.Foreground.tertiary)
            .frame(minHeight: 44)
            .accessibilityIdentifier("habit.notifications.settings.quiet")
        case .summarized:
            Button(action: openNotificationSettings) {
                Label("In Scheduled Summary — Open Settings", systemImage: "list.bullet.rectangle")
            }
            .font(ListsTypography.footnote)
            .foregroundStyle(ListsTokens.Foreground.tertiary)
            .frame(minHeight: 44)
            .accessibilityIdentifier("habit.notifications.settings.summary")
        case .enabled, .none:
            EmptyView()
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                    Text("Current progress")
                        .font(ListsTypography.footnote.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                    Text(progressTitle)
                        .font(ListsTypography.title1.bold())
                        .foregroundStyle(ListsTokens.Foreground.primary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: ListsSpacing.s3)
                Image(systemName: isAtGoal ? "checkmark.circle.fill" : "circle.dotted.circle")
                    .font(.title2)
                    .foregroundStyle(isAtGoal ? ListsTokens.Semantic.success : ListsTokens.accent)
                    .accessibilityHidden(true)
            }

            ProgressView(value: Double(currentCount), total: Double(max(1, item.goalPerCycle)))
                .tint(isAtGoal ? ListsTokens.Semantic.success : ListsTokens.accent)
                .accessibilityLabel("Progress \(HabitStats.cycleNoun(for: cadence))")
                .accessibilityValue("\(currentCount) of \(item.goalPerCycle)")

            Button { perform(.log) } label: {
                HStack(spacing: ListsSpacing.s2) {
                    if activeOperation == .log {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isAtGoal ? "checkmark" : "plus")
                    }
                    Text(isAtGoal ? "Goal Reached" : "Log Completion")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // Habit detail can be presented from list surfaces that tint their
            // descendants with `.primary`. A prominent button would then be
            // white-on-white in dark mode, so keep this action explicitly tied
            // to the product accent.
            .tint(isAtGoal ? ListsTokens.Semantic.success : ListsTokens.accent)
            .controlSize(.large)
            .disabled(isAtGoal || activeOperation != nil)
            .accessibilityIdentifier("habit.completion.log")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ListsSpacing.s4) { progressSecondaryActions }
                VStack(alignment: .leading, spacing: ListsSpacing.s2) { progressSecondaryActions }
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: currentCount
        )
    }

    @ViewBuilder
    private var progressSecondaryActions: some View {
        if currentCount > 0 {
            Button("Undo Latest", systemImage: "arrow.uturn.backward") {
                perform(.undo)
            }
            .disabled(activeOperation != nil)
            .frame(minHeight: 44)
            .accessibilityIdentifier("habit.completion.undo")
        }

        Button("Add with Date", systemImage: "calendar.badge.plus") {
            onAddCompletion(actionNow())
        }
        .disabled(activeOperation != nil)
        .frame(minHeight: 44)
        .accessibilityIdentifier("habit.completion.add")
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text("Recent activity")
                .font(ListsTypography.footnote.weight(.semibold))
                .foregroundStyle(ListsTokens.Foreground.secondary)

            Text(activitySummary)
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.primary)
                .fixedSize(horizontal: false, vertical: true)

            Chart {
                ForEach(lifetimeActivityPoints) { point in
                    BarMark(
                        x: .value("Cycle", point.start),
                        y: .value("Completions", point.count)
                    )
                    .foregroundStyle(
                        point.count >= item.goalPerCycle
                            ? ListsTokens.accent
                            : ListsTokens.accent.opacity(0.35)
                    )
                    .accessibilityLabel(activityLabel(for: point.start))
                    .accessibilityValue("\(point.count) completions; goal \(item.goalPerCycle)")
                }

                RuleMark(y: .value("Goal", item.goalPerCycle))
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(item.goalPerCycle)")
                            .font(ListsTypography.caption2)
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                    .accessibilityLabel("Goal")
                    .accessibilityValue("\(item.goalPerCycle) completions")
            }
            .chartYScale(domain: 0...activityUpperBound)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(activityAxisLabel(for: date))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 210 : 150)
            .accessibilityLabel("Recent habit activity")
            .accessibilityValue(activitySummary)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.22),
                value: currentCount
            )

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ListsSpacing.s5) { secondaryStats }
                VStack(alignment: .leading, spacing: ListsSpacing.s2) { secondaryStats }
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    @ViewBuilder
    private var secondaryStats: some View {
        if item.showStreak {
            Label(currentRunLabel, systemImage: "calendar.badge.checkmark")
                .accessibilityLabel("Current run")
                .accessibilityValue(currentRunValue)
        }

        Label("\(HabitStats.totalCompletions(for: item)) total", systemImage: "checkmark.circle")
            .accessibilityLabel("Total completions")
            .accessibilityValue("\(HabitStats.totalCompletions(for: item))")
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            HStack {
                Text("Recent completions")
                    .font(ListsTypography.footnote.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Spacer()
                if !item.completions.isEmpty {
                    NavigationLink {
                        HabitCompletionLogView(
                            habitId: item.id,
                            store: store,
                            onAddCompletion: { onAddCompletion(actionNow()) },
                            onEditCompletion: onEditCompletion
                        )
                    } label: {
                        Text("History").font(ListsTypography.footnote)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("habit.history.open")
                }
            }

            if recentEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Completions Yet", systemImage: "checkmark.circle")
                } description: {
                    Text("Log one when you complete this habit.")
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(recentEntries) { entry in
                    Button { onEditCompletion(entry) } label: {
                        recentRow(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recentEntryAccessibilityLabel(entry))
                    .accessibilityHint("Opens this completion for editing")
                    .accessibilityIdentifier(
                        "habit.recent.entry.\(entry.id.uuidString.lowercased())"
                    )

                    if entry.id != recentEntries.last?.id { Divider() }
                }
            }
        }
        .padding(ListsSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func recentRow(_ entry: HabitCompletion) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ListsSpacing.s3) {
                completionGlyph
                Text(Self.entryDateFormatter.string(from: entry.at))
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Spacer()
                Text(Self.timeFormatter.string(from: entry.at))
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
            }

            HStack(alignment: .top, spacing: ListsSpacing.s3) {
                completionGlyph
                VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                    Text(Self.entryDateFormatter.string(from: entry.at))
                        .foregroundStyle(ListsTokens.Foreground.primary)
                    Text(Self.timeFormatter.string(from: entry.at))
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }

    private var completionGlyph: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(ListsTokens.accent)
            .accessibilityHidden(true)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private var cadence: HabitFrequency {
        (item.frequency ?? .daily).normalizedForHabit
    }

    private var currentCount: Int {
        count(in: item, on: now)
    }

    private var isAtGoal: Bool { currentCount >= item.goalPerCycle }

    private var habitSummary: String {
        let goal = item.goalPerCycle
        return "\(cadence.habitDisplayName) · Goal \(goal) \(goal == 1 ? "time" : "times") \(HabitStats.cycleNoun(for: cadence))"
    }

    private var progressTitle: String {
        "\(currentCount) of \(item.goalPerCycle) \(HabitStats.cycleNoun(for: cadence))"
    }

    private var hasReminder: Bool {
        item.reminder?.enabled == true && item.due != nil
    }

    private var reminderTaskID: String {
        "\(hasReminder)-\(item.modifiedAt.timeIntervalSince1970)"
    }

    private var activityLimit: Int {
        switch cadence {
        case .weekly: 12
        case .monthly: 12
        default: 14
        }
    }

    private var activityPoints: [ActivityPoint] {
        HabitStats.recentCycles(for: item, limit: activityLimit, now: now).map {
            ActivityPoint(id: $0.key, start: $0.start, count: $0.count)
        }
    }

    private var activityUpperBound: Int {
        max(max(item.goalPerCycle, lifetimeActivityPoints.map(\.count).max() ?? 0), 1) + 1
    }

    private var lifetimeActivityPoints: [ActivityPoint] {
        let creationKey = HabitCycle.key(for: cadence, on: item.createdAt)
        if let creationIndex = activityPoints.firstIndex(where: { $0.id == creationKey }) {
            return Array(activityPoints[creationIndex...])
        } else if let oldest = activityPoints.first, item.createdAt <= oldest.start {
            return activityPoints
        }
        return []
    }

    private var activitySummary: String {
        let currentKey = HabitCycle.key(for: cadence, on: now)
        let completedCycles = lifetimeActivityPoints.filter { $0.id != currentKey }
        let met = completedCycles.filter { $0.count >= item.goalPerCycle }.count
        let cycles = completedCycles.count
        guard cycles > 0 else { return "No completed cycles yet." }
        return "Goal met in \(met) of the last \(cycles) \(cycles == 1 ? "cycle" : "cycles")."
    }

    private var currentRunValue: String {
        let run = HabitStats.streak(for: item, now: now)
        let unit: String
        switch cadence {
        case .weekly: unit = run == 1 ? "week" : "weeks"
        case .monthly: unit = run == 1 ? "month" : "months"
        default: unit = run == 1 ? "day" : "days"
        }
        return "\(run) \(unit)"
    }

    private var currentRunLabel: String { "Current run: \(currentRunValue)" }

    private var recentEntries: [HabitCompletion] {
        Array(item.completions.sorted { $0.at > $1.at }.prefix(4))
    }

    private var isShowingOperationFailure: Binding<Bool> {
        Binding(
            get: { operationFailure != nil },
            set: { isPresented in
                if !isPresented { operationFailure = nil }
            }
        )
    }

    private func perform(
        _ operation: CompletionOperation,
        actionDate suppliedActionDate: Date? = nil
    ) {
        guard activeOperation == nil else { return }
        let actionDate = suppliedActionDate ?? actionNow()
        let countBefore = count(in: store.item(item.id) ?? item, on: actionDate)
        activeOperation = operation
        operationFailure = nil

        Task {
            do {
                switch operation {
                case .log:
                    try await store.incrementHabit(item.id, now: actionDate)
                case .undo:
                    try await store.removeLatestCompletion(in: actionDate, for: item.id)
                }
                activeOperation = nil

                if operation == .log,
                   countBefore < item.goalPerCycle,
                   count(in: store.item(item.id) ?? item, on: actionDate) >= item.goalPerCycle {
                    goalFeedback += 1
                }
            } catch {
                activeOperation = nil
                operationFailure = CompletionFailure(
                    operation: operation,
                    actionDate: actionDate,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func retryFailedOperation() {
        guard let failure = operationFailure else { return }
        operationFailure = nil
        perform(failure.operation, actionDate: failure.actionDate)
    }

    private func count(in source: Item, on date: Date) -> Int {
        let sourceCadence = (source.frequency ?? .daily).normalizedForHabit
        let key = HabitCycle.key(for: sourceCadence, on: date)
        return source.completions.reduce(into: 0) { result, completion in
            if HabitCycle.key(for: sourceCadence, on: completion.at) == key {
                result += 1
            }
        }
    }

    private func refreshNotificationStatus(
        forceRescheduleIfUsable: Bool = false,
        rescheduleOnRecovery: Bool = true
    ) async {
        guard hasReminder else {
            notificationStatus = nil
            return
        }
        let previousStatus = notificationStatus
        let refreshedStatus = await notificationStatusProvider()
        notificationStatus = refreshedStatus

        let recovered = HabitNotificationStatus.shouldRescheduleAfterRecovery(
            from: previousStatus,
            to: refreshedStatus
        )
        if refreshedStatus.canDeliver,
           forceRescheduleIfUsable || (rescheduleOnRecovery && recovered) {
            await rescheduleReminder(item)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        awaitingNotificationSettingsReturn = true
        openURL(url)
    }

    private func activityAxisLabel(for date: Date) -> String {
        switch cadence {
        case .weekly:
            return weekStart(containing: date)
                .formatted(.dateTime.month(.abbreviated).day())
        case .monthly:
            return date.formatted(.dateTime.month(.abbreviated))
        default:
            return date.formatted(.dateTime.weekday(.narrow).day())
        }
    }

    private func activityLabel(for date: Date) -> String {
        switch cadence {
        case .weekly:
            let start = weekStart(containing: date)
            return "Week of \(start.formatted(date: .abbreviated, time: .omitted))"
        case .monthly:
            return date.formatted(.dateTime.month(.wide).year())
        default:
            return date.formatted(date: .complete, time: .omitted)
        }
    }

    private func recentEntryAccessibilityLabel(_ entry: HabitCompletion) -> String {
        "Completion on \(Self.entryDateFormatter.string(from: entry.at)) at \(Self.timeFormatter.string(from: entry.at))"
    }

    private func weekStart(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let entryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
