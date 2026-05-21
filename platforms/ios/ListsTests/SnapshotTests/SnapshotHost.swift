import SwiftUI

/// Wrapper for views that need `@Binding`s the test owns.
///
/// Usage:
///     SnapshotHost { isInteracting in
///         FloatingAddButton(action: {}, isInteracting: isInteracting)
///     }
struct SnapshotHostBool<Content: View>: View {
    @State private var value: Bool
    let content: (Binding<Bool>) -> Content

    init(initial: Bool = false, @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

/// Wrapper for views that take a `Binding<String>`.
struct SnapshotHostString<Content: View>: View {
    @State private var value: String
    let content: (Binding<String>) -> Content

    init(initial: String = "", @ViewBuilder content: @escaping (Binding<String>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
