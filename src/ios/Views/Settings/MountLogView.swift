//
//  MountLogView.swift
//  MinisApp
//
//  Mount diagnostics. Everything the mount pipeline logs goes through
//  `AppLogger(category: "MountedFolders")` (manager) and
//  `AppLogger(category: "MountedFoldersUI")` (this screen), plus the
//  `MOUNT-DIAG` lines pushed to the iSH coordinator. Those categories are the
//  only way to tell apart the failure modes that all look identical in the
//  UI ("nothing happened"): the picker never called back, the bookmark was
//  rejected, the security scope was denied, or the provider evicted the
//  contents.
//
//  This screen exists because the general Logs page is behind Settings ▸ Logs,
//  needs capture switched on, and mixes mount lines with everything else. Here
//  the filter is fixed and capture is force-enabled on appear, so a user
//  reporting "mounting still does nothing" can hand over one screen of text.
//

import SwiftUI
import UIKit

struct MountLogView: View {
    @ObservedObject private var logging = LoggingManager.shared

    @State private var lines: [String] = []
    @State private var isLoading = true
    @State private var didEnableCapture = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(AppLocalized("Reading logs…"))
            } else if lines.isEmpty {
                // Hand-rolled rather than `ContentUnavailableView`: the app
                // target still deploys to iOS 16 and that type is iOS 17+.
                VStack(spacing: 10) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(AppLocalized("No mount log lines yet"))
                        .font(.headline)
                    Text(AppLocalized("Capture is now on. Go back, try adding a folder again, then return here — every step of the attempt is recorded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(AppLocalized("Mount Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        reload()
                    } label: {
                        Label(AppLocalized("Refresh"), systemImage: "arrow.clockwise")
                    }
                    Button {
                        exportLines()
                    } label: {
                        Label(AppLocalized("Share Log"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(lines.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                MountLogShareSheet(urls: [exportURL])
            }
        }
        .onAppear(perform: prepare)
    }

    private func prepare() {
        // [T-mount-log-capture] Capture defaults to OFF, and a user reporting a
        // mount failure has almost certainly never turned it on — which is why
        // earlier reports arrived with no usable log. Turning it on here means
        // the *next* attempt is recorded even if this visit found nothing.
        if !logging.isEnabled, !didEnableCapture {
            didEnableCapture = true
            logging.isEnabled = true
        }
        reload()
    }

    private func reload() {
        isLoading = true
        let files = LoggingManager.shared.logFiles()
        let newest = files.first?.url
        Task.detached(priority: .userInitiated) {
            var collected: [String] = []
            // Newest first, and only the newest file: mount attempts are always
            // the tail of the current day's log, and reading every file would
            // stall on multi-hundred-MB days.
            if let newest {
                let text = LoggingManager.shared.readLog(at: newest, maxBytes: 4 * 1024 * 1024)
                for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    let line = String(raw)
                    // `AppLogger` writes "[HH:mm:ss] [<category>] <message>", so
                    // the category is what identifies a mount line; the message
                    // body is free-form and can say anything.
                    let isMountCategory = line.contains("[MountedFolders]")
                        || line.contains("[MountedFoldersUI]")
                        || line.contains("MOUNT-DIAG")
                    if isMountCategory { collected.append(line) }
                }
            }
            // Keep the tail: the last attempt is what matters.
            let tail = collected.suffix(600)
            await MainActor.run {
                lines = Array(tail)
                isLoading = false
            }
        }
    }

    private func exportLines() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minis-mount-log-\(stamp).txt")
        let body = lines.joined(separator: "\n")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showShareSheet = true
        } catch {
            AppLogger(category: "MountedFoldersUI")
                .error("[Mount] failed to write log export: \(error.localizedDescription)")
        }
    }
}

private struct MountLogShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let safe = urls.map { MinisShareSheet.sanitizedShareURL($0) ?? $0 }
        return UIActivityViewController(activityItems: safe, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
