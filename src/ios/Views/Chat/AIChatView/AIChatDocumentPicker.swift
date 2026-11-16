import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// [T-file-import-silent-failure] Document picker presented as a UIKit
/// controller instead of SwiftUI's `.fileImporter`.
///
/// `.fileImporter` gave us two problems that could not be diagnosed from a
/// device log, because both end in silence:
///
/// * Its completion closure can be dropped when the hosting view's modifier
///   chain is rebuilt while the picker is on screen. `AIChatView.body` is an
///   ~80-modifier chain over an `AnyView` and recomputes on every `@Published`
///   tick, so a rebuild mid-presentation is the normal case here, not an edge
///   case. The picker closes, the closure never runs, nothing is logged.
/// * There is no cancellation callback, so "user picked nothing" and "the
///   callback was lost" look identical.
///
/// `UIDocumentPickerViewController` is what the app already uses successfully
/// for Files import (`FileBrowserView.swift`), and it gives us an explicit
/// delegate with `didPickDocumentsAt` and `documentPickerWasCancelled`. Both
/// are logged, so the next report can be classified without a rebuild.
///
/// `asCopy: true` matters for the same reason `AIChatFileStaging` exists: the
/// picker hands back a copy in our own temp directory, so a file that lives in
/// iCloud Drive or a third-party provider is downloaded by the picker itself
/// and arrives with no security scope to negotiate.
struct AIChatDocumentPicker: UIViewControllerRepresentable {
    /// Content types offered. `nil` means "everything" (`.item`).
    var contentTypes: [UTType]?
    var allowsMultipleSelection: Bool = true
    /// Called with the picked URLs. Always on the main actor.
    var onPick: ([URL]) -> Void
    /// Called when the user dismisses without picking.
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = contentTypes ?? [.item]
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // The picker is configured once; SwiftUI re-invoking this must not
        // reset the delegate or the selection mode mid-flight.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            AppLogger(category: "FileImport").info("[FileImport] picker didPick \(urls.count) url(s)")
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            AppLogger(category: "FileImport").info("[FileImport] picker cancelled")
            onCancel()
        }
    }
}
