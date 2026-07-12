import PencilKit
import SwiftUI

struct MarkdownDrawingEditor: View {
    let isEditing: Bool
    let onComplete: (PKDrawing?) -> Void
    @State private var drawing: PKDrawing

    init(
        drawing: PKDrawing = PKDrawing(),
        isEditing: Bool = false,
        onComplete: @escaping (PKDrawing?) -> Void
    ) {
        self.isEditing = isEditing
        self.onComplete = onComplete
        _drawing = State(initialValue: drawing)
    }

    var body: some View {
        NavigationStack {
            PencilCanvas(drawing: $drawing)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Drawing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onComplete(nil) }
                            .accessibilityIdentifier("document.drawing.cancel")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "Save" : "Add") { onComplete(drawing) }
                            .fontWeight(.semibold)
                            .disabled(drawing.strokes.isEmpty)
                            .accessibilityIdentifier(isEditing ? "document.drawing.save" : "document.drawing.add")
                    }
                }
        }
        .accessibilityIdentifier("document.drawing.editor")
    }
}

private struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = .systemBackground
        canvas.accessibilityIdentifier = "document.drawing.canvas"
        context.coordinator.canvas = canvas
        DispatchQueue.main.async { context.coordinator.showTools() }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let drawing: Binding<PKDrawing>
        private let toolPicker = PKToolPicker()
        weak var canvas: PKCanvasView?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func showTools() {
            guard let canvas else { return }
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
