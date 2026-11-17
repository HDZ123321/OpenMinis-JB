//
//  LocalFolderBrowserView.swift
//  MinisApp
//
//  A folder browser for directories that already live inside Minis' own
//  container. It exists because the document picker cannot reach them:
//  `UIDocumentPickerViewController` opens in a FileProvider domain (Minis'
//  iCloud container, or "On My iPhone"), and the app's own Documents,
//  Library and rootfs directories are not FileProvider domains at all —
//  `Info.plist` has no `UIFileSharingEnabled`, so they do not appear under
//  "On My iPhone → Minis" either. Users who keep their working files in
//  Minis' workspace or in the Alpine rootfs therefore had no way to mount
//  them, and the picker showed an empty, fully-greyed list.
//
//  [T-mount-local-container] Folders picked here need no security scope:
//  they are inside our sandbox already. `MountedFoldersManager` records
//  `isLocalContainer: true` on the entry so activation does not treat the
//  unavoidable `startAccessingSecurityScopedResource() == false` as a
//  permission denial on the next launch.
//

import SwiftUI

/// One place the browser can start from.
private struct LocalFolderRoot: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
    let symbol: String

    /// Only roots whose directory actually exists are offered — a fresh
    /// install has no rootfs and no App Group container until first boot.
    static func available() -> [LocalFolderRoot] {
        let fm = FileManager.default
        var roots: [LocalFolderRoot] = []

        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documents, fm.fileExists(atPath: documents.path) {
            roots.append(LocalFolderRoot(
                id: "documents",
                title: AppLocalized("App Documents"),
                subtitle: AppLocalized("Files this app writes outside the sandbox-visible areas."),
                url: documents,
                symbol: "doc.fill"
            ))
        }

        let minisData = AIChatViewModel.minisPersistentBase
        if fm.fileExists(atPath: minisData.path) {
            roots.append(LocalFolderRoot(
                id: "minis-data",
                title: AppLocalized("Minis data"),
                subtitle: AppLocalized("Per-session workspace, attachments and offloads."),
                url: minisData,
                symbol: "square.stack.3d.up.fill"
            ))
        }

        let shared = AIChatViewModel.minisAppGroupRoot
        if fm.fileExists(atPath: shared.path) {
            roots.append(LocalFolderRoot(
                id: "shared",
                title: AppLocalized("Shared folder"),
                subtitle: AppLocalized("The same folder Browse Files shows as Minis → shared."),
                url: shared,
                symbol: "folder.fill"
            ))
        }

        let config = AIChatViewModel.minisConfigRoot
        if fm.fileExists(atPath: config.path) {
            roots.append(LocalFolderRoot(
                id: "config",
                title: AppLocalized("Minis config"),
                subtitle: AppLocalized("Skills, memory, MCP servers and mount metadata."),
                url: config,
                symbol: "gearshape.fill"
            ))
        }

        let rootfsData = RootfsManager.shared.dataPath
        if fm.fileExists(atPath: rootfsData.path) {
            roots.append(LocalFolderRoot(
                id: "rootfs",
                title: AppLocalized("Alpine rootfs"),
                subtitle: AppLocalized("The Linux filesystem the shell runs in."),
                url: rootfsData,
                symbol: "terminal.fill"
            ))
        }

        return roots
    }
}

/// Directory browser over the app's own container.
///
/// Navigation is a plain path array rather than a `NavigationStack`, because
/// this view is presented inside a sheet that is already driven by a single
/// `.sheet(item:)` on the mount screen — nesting another presentation
/// container there is what produced the original "tap 打开, nothing happens"
/// class of bug.
struct LocalFolderBrowserView: View {
    /// Called with the folder the user chose. Always on the main actor.
    let onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    @State private var roots: [LocalFolderRoot] = []
    /// Empty = the root list. Each element is a directory we descended into.
    @State private var stack: [URL] = []

    private var currentURL: URL? { stack.last }

    var body: some View {
        NavigationStack {
            List {
                if let current = currentURL {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } footer: {
                        Text(AppLocalized("Mounting a folder that is already inside Minis is fine — it is just a second path to the same files, which is handy when a session's workspace should be readable at a stable location."))
                            .font(.caption2)
                    }

                    let children = Self.subdirectories(of: current)
                    if children.isEmpty {
                        Section {
                            Text(AppLocalized("No subfolders here."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section(AppLocalized("Subfolders")) {
                            ForEach(children, id: \.self) { child in
                                Button {
                                    stack.append(child)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.blue)
                                        Text(child.lastPathComponent)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        if roots.isEmpty {
                            Text(AppLocalized("No browsable folder was found in this app's container."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(roots) { root in
                                Button {
                                    stack = [root.url]
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: root.symbol)
                                            .foregroundStyle(.orange)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(root.title)
                                                .foregroundStyle(.primary)
                                            Text(root.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(AppLocalized("Locations"))
                    } footer: {
                        Text(AppLocalized("These folders live inside Minis itself, so the document picker cannot show them. Pick a location, open the folder you want, then tap Mount This Folder."))
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle(currentURL?.lastPathComponent ?? AppLocalized("Add Local Folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel"), action: onCancel)
                }
                if let current = currentURL {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalized("Mount")) { onPick(current) }
                    }
                }
            }
            .onAppear {
                if roots.isEmpty { roots = LocalFolderRoot.available() }
            }
        }
    }

    /// Immediate subdirectories of `dir`, hidden files and symlinks excluded.
    ///
    /// Symlinks are skipped on purpose: `/var/minis/mounts/<name>` entries are
    /// symlinks to other mounts, and following one would let the browser walk
    /// in a circle. `resourceValues` follows symlinks, so the check has to use
    /// `isSymbolicLinkKey` explicitly rather than `isDirectoryKey` alone.
    private static func subdirectories(of dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                return false
            }
            if values.isSymbolicLink == true { return false }
            return values.isDirectory == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
