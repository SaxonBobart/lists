import Foundation
import Observation

/// One creation surface owns one session. Requests contain value snapshots;
/// neither inference nor its timeout is allowed to write a stored item.
@MainActor
@Observable
final class ItemDescriptionSession {
    private(set) var isAnalyzing = false
    private(set) var statusMessage: String?
    private(set) var availability: ItemDescriptionAvailability

    @ObservationIgnored private let interpreter: any ItemDescriptionInterpreting
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var operation: ItemDescriptionOperation?

    init(
        interpreter: any ItemDescriptionInterpreting = FoundationItemDescriptionInterpreter(),
        debounce: Duration = .milliseconds(700),
        timeout: Duration = .seconds(30)
    ) {
        self.interpreter = interpreter
        self.debounce = debounce
        self.timeout = timeout
        availability = interpreter.availability(locale: .current)
    }

    func schedule(
        _ request: ItemDescriptionRequest,
        onResult: @escaping @MainActor (ItemDescriptionExtraction) -> Void
    ) {
        cancel()
        guard prepare(request) else { return }
        let requestGeneration = generation
        work = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, self.generation == requestGeneration, !Task.isCancelled else { return }
            if let result = await self.perform(request, generation: requestGeneration) {
                onResult(result)
            }
        }
    }

    /// Finishing an inline creation can skip the typing debounce. The result
    /// still has the same cancellation, availability and timeout guarantees.
    func resolve(_ request: ItemDescriptionRequest) async -> ItemDescriptionExtraction? {
        cancel()
        guard prepare(request) else { return nil }
        return await perform(request, generation: generation)
    }

    func cancel() {
        generation &+= 1
        work?.cancel()
        work = nil
        operation?.cancel()
        operation = nil
        isAnalyzing = false
        statusMessage = nil
    }

    private func prepare(_ request: ItemDescriptionRequest) -> Bool {
        availability = interpreter.availability(locale: Locale(identifier: request.localeIdentifier))
        guard !request.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { statusMessage = reason }
            return false
        }
        isAnalyzing = true
        return true
    }

    private func perform(
        _ request: ItemDescriptionRequest,
        generation requestGeneration: UInt64
    ) async -> ItemDescriptionExtraction? {
        let operation = ItemDescriptionOperation()
        self.operation = operation
        let result = await operation.run(interpreter: interpreter, request: request, timeout: timeout)
        guard generation == requestGeneration, !Task.isCancelled else { return nil }
        self.operation = nil
        isAnalyzing = false
        switch result {
        case .success(let extraction):
            statusMessage = nil
            return extraction
        case .failure(is CancellationError):
            return nil
        case .failure(let error):
            statusMessage = (error as? ItemDescriptionInterpretationError)?.errorDescription
                ?? "Couldn’t fill in the details in time. You can enter them manually."
            return nil
        }
    }
}

/// The worker and deadline are intentionally unstructured: a model that takes
/// time to acknowledge cancellation must not keep a dismissed creation surface
/// or a timeout waiting for a task-group child. This main-actor owner resumes
/// its continuation once, cancels both tasks, and ignores any late result.
@MainActor
private final class ItemDescriptionOperation {
    private enum Failure: Error { case timedOut }
    private var continuation: CheckedContinuation<Result<ItemDescriptionExtraction, Error>, Never>?
    private var result: Result<ItemDescriptionExtraction, Error>?
    private var worker: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    func run(
        interpreter: any ItemDescriptionInterpreting,
        request: ItemDescriptionRequest,
        timeout: Duration
    ) async -> Result<ItemDescriptionExtraction, Error> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let result { continuation.resume(returning: result); return }
                self.continuation = continuation
                guard !Task.isCancelled else { cancel(); return }
                worker = Task { [weak self] in
                    let result: Result<ItemDescriptionExtraction, Error>
                    do { result = .success(try await interpreter.extract(request)) }
                    catch { result = .failure(error) }
                    self?.finish(result)
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(.failure(Failure.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<ItemDescriptionExtraction, Error>) {
        guard self.result == nil else { return }
        self.result = result
        worker?.cancel()
        deadline?.cancel()
        worker = nil
        deadline = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Only creation fields participate. Identity, hierarchy, order, completion,
/// provenance and attachments always remain on the current item.
enum ItemDescriptionMerge {
    static func applying(
        _ extraction: ItemDescriptionExtraction,
        to current: Item,
        lockedFields: Set<ItemDescriptionField> = []
    ) -> Item {
        let proposal = extraction.item
        var item = current
        if !lockedFields.contains(.title) { item.title = proposal.title }
        if !lockedFields.contains(.body) { item.body = proposal.body }
        if !lockedFields.contains(.schedule) {
            item.due = proposal.due
            item.end = proposal.end
            item.dueAllDay = proposal.dueAllDay
            item.dueTimeZone = proposal.dueTimeZone
        }
        if !lockedFields.contains(.reminder) { item.reminder = proposal.reminder }
        if !lockedFields.contains(.alarm) { item.triggers?.alarm = proposal.triggers?.alarm }
        if !lockedFields.contains(.alarm), item.triggers == nil, proposal.triggers?.alarm != nil {
            item.triggers = Triggers(alarm: proposal.triggers?.alarm)
        }
        if !lockedFields.contains(.recurrence) { item.recurrence = proposal.recurrence }
        if !lockedFields.contains(.flagged) { item.flagged = proposal.flagged }
        if !lockedFields.contains(.priority) { item.priority = proposal.priority }
        if !lockedFields.contains(.tags) { item.tags = proposal.tags }
        if !lockedFields.contains(.list) { item.listId = proposal.listId }
        if !lockedFields.contains(.section) { item.section = proposal.section }
        if !lockedFields.contains(.completable) { item.completable = proposal.completable }
        return item
    }

    static func detectingChangedFields(current: Item, previous: Item) -> Set<ItemDescriptionField> {
        var fields: Set<ItemDescriptionField> = []
        if current.title != previous.title { fields.insert(.title) }
        if current.body != previous.body { fields.insert(.body) }
        if current.due != previous.due || current.end != previous.end
            || current.dueAllDay != previous.dueAllDay || current.dueTimeZone != previous.dueTimeZone {
            fields.insert(.schedule)
        }
        if current.reminder != previous.reminder { fields.insert(.reminder) }
        if current.triggers?.alarm != previous.triggers?.alarm { fields.insert(.alarm) }
        if current.recurrence != previous.recurrence { fields.insert(.recurrence) }
        if current.flagged != previous.flagged { fields.insert(.flagged) }
        if current.priority != previous.priority { fields.insert(.priority) }
        if current.tags != previous.tags { fields.insert(.tags) }
        if current.listId != previous.listId { fields.formUnion([.list, .section]) }
        if current.section != previous.section { fields.insert(.section) }
        if current.completable != previous.completable { fields.insert(.completable) }
        return fields
    }
}
