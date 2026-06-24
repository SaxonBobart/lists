import SwiftUI
import UIKit

struct ExportLibraryView: View {
    let store: ItemStore

    @State private var isExporting = false
    @State private var isShowingShareSheet = false
    @State private var exportURL: URL?
    @State private var status: ExportStatus = .idle

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            VStack(spacing: ListsSpacing.s5) {
                Image(systemName: status.iconName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(status.iconColor)
                    .accessibilityHidden(true)

                Text(status.title)
                    .font(ListsTypography.title3)
                    .multilineTextAlignment(.center)

                Text(status.message)
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ListsSpacing.s7)

                Button {
                    export()
                } label: {
                    Label(isExporting ? "Exporting" : "Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(ListsTokens.accent)
                .disabled(isExporting)
                .accessibilityIdentifier("settings.exportLibrary.run")
            }
            .padding(.top, ListsSpacing.s8)
        }
        .navigationTitle("Export Library")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.exportLibrary.screen")
        .sheet(isPresented: $isShowingShareSheet) {
            if let exportURL {
                ActivityView(items: [exportURL])
            }
        }
    }

    private func export() {
        isExporting = true
        status = .working
        Task {
            do {
                let url = try await store.exportLibrary()
                exportURL = url
                status = .ready(fileName: url.lastPathComponent)
                isShowingShareSheet = true
            } catch {
                status = .failure(error.localizedDescription)
            }
            isExporting = false
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
