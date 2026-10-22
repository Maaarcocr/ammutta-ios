import SwiftUI
import UIKit

/// Something to share, presented by the screen that owns it.
struct ShareItem: Identifiable {
    let id = UUID()
    let content: Any
}

/// The system share sheet, presented from a screen that stays on screen.
///
/// `ShareLink` inside a toolbar overflow menu presents from the menu, which is dismissed as the
/// share sheet appears, and crashed the app. Menu items set a `ShareItem` instead and the
/// screen presents this sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.content], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    func shareSheet(item: Binding<ShareItem?>) -> some View {
        sheet(item: item) { item in
            ShareSheet(item: item)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }
}
