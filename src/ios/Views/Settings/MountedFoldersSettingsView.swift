//
//  MountedFoldersSettingsView.swift
//  MinisApp
//
//  Settings screen for managing user-mounted external folders. Lets the user
//  pick a folder from iOS Files (e.g. an Obsidian vault in iCloud Drive),
//  give it a custom name, and mount it at /var/minis/mounts/<name>.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let mountUILogger = AppLogger(category: "MountedFoldersUI")

/// Wrapper so we can drive the Add-Mount sheet via `.sheet(item:)`, which
/// guarantees the URL is present when the sheet is constructed. Using two
/// stacked `.sheet(isPresented:)` modifiers races on first pick: the
/// AddMountSheet is built before `pendingPickedURL` has propagated, so its
/// "Source path" section renders empty until the next attempt.
private struct PendingMount: Identifiable {
    let id = UUID()
    let url: URL
    var name: String
    var allowWrite: Bool
}

/// One sheet, two steps.
///
/// [T-mount-sheet-single] This used to be two `.sheet` modifiers chained on the
/// same `List` — one `isPresented` for the document picker, one `item` for the
/// Add-Mount form. SwiftUI only honours one sheet per view, so the picker
/// presented and the confirm form never did: the user tapped 打开 and the
/// screen simply went back, with no form and no error. A single `.sheet(item:)`
/// whose identity changes between the two steps is the only shape that works,
/// and `onDismiss` is what guarantees the picker is fully gone before the form
/// is presented (iOS refuses to stack two sheets).
private enum MountFlow: String, Identifiable {
    case picker
    case confirm

    var id: String { rawValue }
}

/// One alert slot for the screen: the picker hint and the add-failure message
/// cannot be two `.alert` modifiers on the same view for the same reason two
/// `.sheet` modifiers could not coexist — SwiftUI keeps one presentation per
/// kind and silently drops the loser.
private enum MountAlert: Identifiable, Equatable {
    case pickerHint
    case failure(String)

    var id: String {
        switch self {
        case .pickerHint: return "pickerHint"
        case .failure: return "failure"
        }
    }
}

struct MountedFoldersSettingsView: View {
    @StateObject private var model = MountedFoldersViewModel()
    @State private var flow: MountFlow?
    /// Which step the sheet most recently rendered. `onDismiss` runs after
    /// `flow` has already been reset to nil, so this is the only way to know
    /// whether the picker or the confirm form just went away — advancing on a
    /// dismissed *confirm* form would re-present it forever (swipe-to-dismiss
    /// leaves `pendingMount` set).
    @State private var stepShown: MountFlow = .picker
    /// Set when the picker returns a folder, consumed by `onDismiss` to present
    /// the confirm step on the next presentation cycle.
    @State private var pendingMount: PendingMount?
    /// One alert slot for the whole screen.
    ///
    /// [T-mount-picker-hint] A second `.alert` modifier on the same view is the
    /// same trap as the second `.sheet` that caused the original bug: SwiftUI
    /// keeps one presentation per kind, so whichever alert loses the race just
    /// never appears. Driving both the error and the first-tap hint through one
    /// enum-backed alert is the only shape that cannot silently drop one.
    @State private var alert: MountAlert?
    /// First-tap explanation, shown before the picker ever appears.
    ///
    /// [T-mount-picker-hint] The picker opens inside Minis' own iCloud
    /// container, which normally holds files but no subfolders — so every row
    /// is greyed out and 打开 does nothing at all. That reads as "the button is
    /// broken" and is exactly how this got reported. Saying where to navigate
    /// *before* the picker opens is the only place the instruction is still
    /// readable; a footnote under an empty list is not seen until afterwards.
    @AppStorage("mount.pickerHintShown") private var pickerHintShown = false

    var body: some View {
        List {
            Section {
                InfoBanner()
            }

            if model.entries.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No mounted folders")
                            .font(.headline)
                        Text("Tap + to pick a folder from Files (e.g. an Obsidian vault in iCloud Drive).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        // [T-mount-sheet-single] The picker opens inside the
                        // Minis container, which usually holds only files and
                        // has no subfolders — the Open button then does nothing
                        // because there is nothing selectable. Tell the user
                        // where to navigate instead of letting them conclude
                        // the feature is broken.
                        Text("In the picker, switch to Browse → On My iPhone or iCloud Drive, open the folder you want, then tap Open.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ForEach(model.entries) { entry in
                        NavigationLink {
                            MountDetailView(
                                context: detailContext(for: entry),
                                onDismiss: { model.refresh() }
                            )
                        } label: {
                            MountedFolderRow(
                                entry: entry,
                                state: model.state(for: entry.id),
                                sourceURL: model.resolvedURL(for: entry.id)
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                model.remove(id: entry.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Mounted Folders")
                        Spacer()
                        Text("\(model.entries.count) / \(MountedFoldersManager.maxMountCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(model.isAtCapacity ? .orange : .secondary)
                    }
                } footer: {
                    if model.isAtCapacity {
                        Text("Mount limit reached. Remove an existing mount before adding a new one.")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Mount External Folders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if pickerHintShown {
                        stepShown = .picker
                        flow = .picker
                    } else {
                        pickerHintShown = true
                        alert = .pickerHint
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(model.isAtCapacity)
            }
        }
        .sheet(item: $flow, onDismiss: {
            // [T-mount-sheet-single] The picker and the confirm form cannot be
            // two `.sheet` modifiers on one view — SwiftUI presents the first
            // and silently drops the second, which is exactly the "tap 打开,
            // nothing happens" report. One sheet whose identity changes drives
            // both steps; this hook is what advances picker → form, and it only
            // runs once the picker has actually left the hierarchy (iOS refuses
            // to stack two sheets).
            if stepShown == .picker, let picked = pendingMount {
                mountUILogger.info("[Mount] advancing to confirm step for \(picked.url.path)")
                // Hopping one tick is deliberate: `onDismiss` runs while the
                // picker's dismissal animation is still settling, and setting a
                // new sheet identity synchronously there can be swallowed the
                // same way the two-modifier version was.
                DispatchQueue.main.async {
                    stepShown = .confirm
                    flow = .confirm
                }
            } else if stepShown == .confirm {
                // The confirm form went away (mounted, cancelled, or swiped).
                // Either way the picked URL is spent; keeping it around would
                // leave a stale pending value for the next presentation.
                pendingMount = nil
            }
        }) { step in
            switch step {
            case .picker:
                FolderPicker(
                    onPick: { url in
                        mountUILogger.info("[Mount] picker returned \(url.path) (isDirectory=\(Self.isDirectory(url)))")
                        guard Self.isDirectory(url) else {
                            // A `.folder` picker should never hand back a file,
                            // but third-party providers have been seen doing it.
                            // Say so instead of opening a form that will fail on
                            // bookmarkData().
                            pendingMount = nil
                            flow = nil
                            // Present after the sheet has actually gone: an
                            // alert raised in the same update as a sheet
                            // dismissal loses the race the same way the second
                            // sheet did.
                            DispatchQueue.main.async {
                                alert = .failure(AppLocalized("The item you picked is a file, not a folder. Open the folder first, then tap Open."))
                            }
                            return
                        }
                        pendingMount = PendingMount(
                            url: url,
                            name: Self.defaultMountName(for: url),
                            allowWrite: true
                        )
                        flow = nil
                    },
                    onCancel: {
                        mountUILogger.info("[Mount] picker cancelled with no selection")
                        pendingMount = nil
                        flow = nil
                    }
                )
            case .confirm:
                if let pending = pendingMount {
                    AddMountSheet(
                        sourceURL: pending.url,
                        name: Binding(
                            get: { pendingMount?.name ?? pending.name },
                            set: { pendingMount?.name = $0 }
                        ),
                        allowWrite: Binding(
                            get: { pendingMount?.allowWrite ?? pending.allowWrite },
                            set: { pendingMount?.allowWrite = $0 }
                        ),
                        onCancel: {
                            pendingMount = nil
                            flow = nil
                        },
                        onConfirm: {
                            let current = pendingMount ?? pending
                            mountUILogger.info("[Mount] confirm name=\(current.name) write=\(current.allowWrite) url=\(current.url.path)")
                            do {
                                _ = try model.add(
                                    pickedURL: current.url,
                                    customName: current.name,
                                    userAllowWrite: current.allowWrite
                                )
                                mountUILogger.info("[Mount] added \(current.name), total=\(model.entries.count)")
                            } catch {
                                mountUILogger.error("[Mount] add failed: \(error.localizedDescription)")
                                let message = error.localizedDescription
                                pendingMount = nil
                                flow = nil
                                DispatchQueue.main.async { alert = .failure(message) }
                                return
                            }
                            pendingMount = nil
                            flow = nil
                        }
                    )
                } else {
                    // Only reachable if state was cleared out from under us.
                    Color.clear.onAppear { flow = nil }
                }
            }
        }
        .alert(alertTitle, isPresented: Binding(
            get: { alert != nil },
            set: { if !$0 { alert = nil } }
        )) {
            if alert == .pickerHint {
                Button(AppLocalized("Got it")) {
                    // Same one-tick hop as everywhere else on this screen: the
                    // alert is still on its way out, and presenting the picker
                    // in the same update is dropped.
                    DispatchQueue.main.async {
                        stepShown = .picker
                        flow = .picker
                    }
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } else {
                Button(AppLocalized("OK"), role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        // Unwrap before switching: Swift does not match bare enum cases against
        // an optional, and a `.none` arm here would only ever fire mid-dismissal.
        guard let alert else { return AppLocalized("Error") }
        switch alert {
        case .pickerHint: return AppLocalized("Pick a folder, not a file")
        case .failure: return AppLocalized("Error")
        }
    }

    private var alertMessage: String {
        guard let alert else { return "" }
        switch alert {
        case .pickerHint:
            return AppLocalized("The picker opens inside Minis' own folder, where there is usually nothing to select — the Open button then does nothing. Switch to Browse → On My iPhone or iCloud Drive first, open the folder you want, then tap Open.")
        case .failure(let message):
            return message
        }
    }

    /// Build the MountDetailView context for an external-mount entry.
    private func detailContext(for entry: MountedFolderEntry) -> MountDetailContext {
        // Host URL for Browse Files goes through the fakefs symlink so the
        // breadcrumb shows /var/minis/mounts/<name>.
        let mountPath = RootfsManager.shared.dataPath
            .appendingPathComponent("var/minis/mounts", isDirectory: true)
            .appendingPathComponent(entry.name)
        return MountDetailContext(
            kind: .external,
            linuxPath: "/var/minis/mounts/\(entry.name)",
            sourceDisplayName: entry.sourceDisplayName,
            hostURL: mountPath,
            iconName: "externaldrive.fill",
            iconColor: .orange,
            subtitle: nil,
            initialName: entry.name,
            canRename: true,
            externalMountId: entry.id,
            isOSWritable: entry.isWritable,
            initialUserAllowWrite: entry.userAllowWrite,
            sharedFolderName: nil,
            initialVisibleInFiles: true,
            isReadOnlyFromFiles: false
        )
    }

    /// Whether the picked URL really is a folder.
    ///
    /// [T-mount-sheet-single] `UIDocumentPickerViewController(forOpeningContentTypes:
    /// [.folder])` is supposed to only return folders, but third-party
    /// FileProviders (and the iCloud container root under some iOS builds) have
    /// been observed handing back a file URL when the user taps 打开 with
    /// nothing selected inside the container. Checking here turns a silent
    /// bookmark failure into a sentence the user can act on.
    private static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory ?? false
    }

    /// Trivial / meaningless segments often appearing at the end of an iCloud
    /// container identifier's reverse-DNS bundle ID (e.g. `iCloud~com~nssurge~inc`
    /// where "inc" is just the company suffix). We skip these when picking a
    /// friendly default mount name.
    private static let trivialSuffixes: Set<String> = [
        "inc", "ltd", "llc", "app", "co", "corp", "gmbh"
    ]

    /// Default mount name suggestion.
    ///
    /// When the user picks an iCloud Drive app folder, `url.lastPathComponent`
    /// is often literally "Documents" because Apple's ubiquity container
    /// structure is:
    ///     .../Mobile Documents/iCloud~<team>~<bundle-parts>/Documents/
    ///
    /// Using "Documents" as the mount name gives no hint about which app the
    /// folder belongs to. We detect that case and instead derive the name
    /// from the parent container, picking the most meaningful segment of the
    /// reverse-DNS bundle ID (e.g. `iCloud~com~nssurge~inc` → `nssurge`, not
    /// `inc`).
    private static func defaultMountName(for url: URL) -> String {
        let lastName = url.lastPathComponent
        let candidate: String
        if lastName == "Documents" {
            // Walk up: parent is the ubiquity container directory.
            let parent = url.deletingLastPathComponent()
            let parentName = parent.lastPathComponent
            if parentName.hasPrefix("iCloud~") {
                // Format: "iCloud~<team>~<bundle-component-1>~<bundle-component-2>..."
                // Drop the "iCloud" prefix and the TLD-like team segment
                // (index 1, usually "com" / "net" / "org" / "io" / "md").
                let parts = parentName.split(separator: "~").map(String.init)
                let remaining = Array(parts.dropFirst(2)) // drop "iCloud" + team
                // Prefer the last segment that isn't a trivial corporate suffix.
                let best = remaining.reversed().first { segment in
                    !Self.trivialSuffixes.contains(segment.lowercased())
                } ?? remaining.last ?? parts.last ?? lastName
                candidate = best
            } else if !parentName.isEmpty {
                // Not an iCloud container but still called Documents —
                // fall back to the parent name for disambiguation.
                candidate = parentName
            } else {
                candidate = lastName
            }
        } else {
            candidate = lastName
        }

        let cleaned = candidate
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "mount" : cleaned
    }
}

// MARK: - Banner

private struct InfoBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Mount external folders", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
            Text("Picked folders are bind-mounted at /var/minis/mounts/<name>. You can browse them in Browse Files and read/write them directly from the iSH shell, just like /var/minis/shared. Up to 10 folders can be mounted at a time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Row

private struct MountedFolderRow: View {
    let entry: MountedFolderEntry
    let state: MountActivationState
    let sourceURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(entry.name)
                    .font(.body.weight(.medium))
                accessBadge
                Spacer()
            }
            Text("/var/minis/mounts/\(entry.name)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "← \(sourceURL?.path ?? entry.sourceDisplayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    /// Small pill reflecting the effective write state of this mount:
    /// - "R/W": the OS allows writes AND the user allowed writes
    /// - "Locked": the OS allows writes but the user set Allow Writes = off
    /// - "Read-only": the OS itself does not allow writes (user choice n/a)
    @ViewBuilder
    private var accessBadge: some View {
        if !entry.isWritable {
            badgePill(text: AppLocalized("Read-only"), color: .orange)
        } else if !entry.userAllowWrite {
            badgePill(text: AppLocalized("Locked"), color: .purple)
        } else {
            badgePill(text: AppLocalized("R/W"), color: .green)
        }
    }

    private func badgePill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Add mount sheet

private struct AddMountSheet: View {
    let sourceURL: URL?
    @Binding var name: String
    @Binding var allowWrite: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let url = sourceURL {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Source path")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(url.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    } footer: {
                        Text("The path above is how iOS exposes the folder you picked. Use it to confirm which app this data belongs to.")
                            .font(.caption2)
                    }
                }

                Section(header: Text("Mount name")) {
                    TextField("name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("This will be the folder name under /var/minis/mounts/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $allowWrite) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow writes")
                            Text(allowWrite
                                ? AppLocalized("AI, shell, and Files browser can modify files in this mount.")
                                : AppLocalized("This mount will be exposed as read-only. Useful for reference vaults you don't want the AI to touch."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("You can change the write permission later from the mount details page.")
                        .font(.caption)
                }
            }
            .navigationTitle("New Mount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalized("Mount"), action: onConfirm)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Folder picker

/// Folder picker for choosing a mount source.
///
/// [T-mount-sheet-single] Two changes from the original:
///  - `onCancel` exists. Without it a cancelled pick and a dropped delegate
///    callback looked identical (sheet disappears, nothing happens), which is
///    the bug this file was reported for.
///  - `asCopy: false` — a mount keeps a security-scoped bookmark to the folder
///    in place. `asCopy: true` would copy the folder into our temp directory
///    and the bookmark would point at a copy that gets deleted, so mounts would
///    appear to work once and then read as empty.
private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                mountUILogger.warning("[Mount] didPickDocumentsAt fired with no URL")
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MountedFoldersViewModel: ObservableObject {
    @Published private(set) var entries: [MountedFolderEntry] = []
    @Published private(set) var states: [UUID: MountActivationState] = [:]

    var isAtCapacity: Bool {
        entries.count >= MountedFoldersManager.maxMountCount
    }

    init() {
        refresh()
    }

    func refresh() {
        entries = MountedFoldersManager.shared.entries
        states = MountedFoldersManager.shared.activationStates
    }

    func state(for id: UUID) -> MountActivationState {
        states[id] ?? .failed("")
    }

    /// Resolved host URL for a mount, if currently active. Exposed to row views
    /// so they can display the underlying iOS filesystem path.
    func resolvedURL(for id: UUID) -> URL? {
        MountedFoldersManager.shared.resolvedURL(for: id)
    }

    @discardableResult
    func add(pickedURL: URL, customName: String, userAllowWrite: Bool) throws -> MountedFolderEntry {
        // The document picker gives a URL with scope active; start it once more
        // defensively so MountedFoldersManager's bookmarkData call inside succeeds.
        let started = pickedURL.startAccessingSecurityScopedResource()
        defer { if started { pickedURL.stopAccessingSecurityScopedResource() } }
        let entry = try MountedFoldersManager.shared.add(
            pickedURL: pickedURL,
            customName: customName,
            userAllowWrite: userAllowWrite
        )
        refresh()
        return entry
    }

    func remove(id: UUID) {
        MountedFoldersManager.shared.remove(id: id)
        refresh()
    }

    func rename(id: UUID, to newName: String) throws {
        try MountedFoldersManager.shared.rename(id: id, to: newName)
        refresh()
    }

    func setUserAllowWrite(id: UUID, to allow: Bool) {
        MountedFoldersManager.shared.setUserAllowWrite(id: id, to: allow)
        refresh()
    }
}
