import Foundation

/// [T-file-import-silent-failure] Staging helper for files picked through the
/// document picker.
///
/// `AIChatViewModel.addFileAttachment(from:)` used to copy straight from the
/// picker's URL with a bare `FileManager.copyItem`. Two real-world picks fail
/// that way, and both failed SILENTLY — one `AppLogger` line and nothing on
/// screen — so "选好文件点打开没反应" was indistinguishable from "the tap did
/// nothing at all":
///
/// 1. **Not-yet-downloaded iCloud Drive / third-party provider files.** The
///    picker hands back a placeholder URL; the bytes only appear after a
///    *coordinated* read asks the provider to materialize the item. A plain
///    `copyItem` throws `NSFileReadNoSuchFileError` (260) instead of
///    downloading, which is the reported symptom whenever the file lives in
///    Files' iCloud Drive or a cloud provider.
/// 2. **Security-scoped URLs.** `startAccessingSecurityScopedResource()`
///    returns false for some providers, and the subsequent copy fails with
///    EPERM. The old code ignored the return value entirely.
///
/// So staging always goes through `NSFileCoordinator`, kicks an explicit
/// download for ubiquitous items that are not current, and — when the provider
/// will hand over bytes but not a copyable file — falls back to a coordinated
/// `Data` read. Every failure comes back as a `StagingError` with a
/// user-presentable `localizedMessage`.
enum AIChatFileStaging {

    enum StagingError: Error {
        /// The URL has no readable bytes at all.
        case sourceMissing
        /// The provider never answered the coordinated read.
        case providerNotResponding
        /// The item exists but the copy threw.
        case copyFailed(String)

        /// Sentence to show the user. Kept out of `errorDescription` because
        /// the file name is appended unlocalized.
        var localizedMessage: String {
            switch self {
            case .sourceMissing:
                return AppLocalized("The file could not be read. If it is stored in iCloud Drive or a cloud provider, download it in the Files app first.")
            case .providerNotResponding:
                return AppLocalized("The document provider did not hand the file over. Open it once in the Files app, then pick it again.")
            case .copyFailed:
                return AppLocalized("The file could not be copied into Minis.")
            }
        }

        /// Extra diagnostic detail, appended in parentheses. Never localized.
        var detail: String? {
            switch self {
            case .sourceMissing, .providerNotResponding:
                return nil
            case .copyFailed(let reason):
                return reason
            }
        }
    }

    /// Copy `source` into `dir` and return the staged URL.
    ///
    /// - Parameter uniquePrefix: when true the staged name gets an 8-character
    ///   random prefix so two picks of the same filename cannot collide. The
    ///   extension is always preserved: downstream type checks (the
    ///   Provider-export JSON gate, the image magic-byte sniff) key off it.
    static func stage(_ source: URL, into dir: URL, uniquePrefix: Bool = true) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let rawName = source.lastPathComponent
        let name = rawName.isEmpty ? "imported" : rawName
        let stagedName: String
        if uniquePrefix {
            stagedName = "\(UUID().uuidString.prefix(8))_\(name)"
        } else {
            stagedName = uniqueName(for: name, in: dir)
        }
        let dest = dir.appendingPathComponent(stagedName)
        try? fm.removeItem(at: dest)

        // A placeholder has no readable bytes yet. Asking for the download
        // first turns the common "iCloud file never opened on this device"
        // case into a wait instead of a hard failure.
        materializeIfNeeded(source)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        var coordError: NSError?
        var copyError: Error?
        var coordinatorRan = false
        var providerBytes: Data?

        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { readURL in
            coordinatorRan = true
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: readURL, to: dest)
            } catch {
                // Provider gave us a URL but not a copyable item (common for
                // File Provider based cloud apps). Keep the bytes route open.
                if let data = try? Data(contentsOf: readURL, options: [.mappedIfSafe]) {
                    providerBytes = data
                } else {
                    copyError = error
                }
            }
        }

        if let providerBytes {
            do {
                try providerBytes.write(to: dest, options: .atomic)
            } catch {
                throw StagingError.copyFailed(error.localizedDescription)
            }
        } else if let copyError {
            if !fm.fileExists(atPath: source.path) {
                throw StagingError.sourceMissing
            }
            throw StagingError.copyFailed(copyError.localizedDescription)
        } else if !coordinatorRan {
            _ = coordError
            throw StagingError.providerNotResponding
        }

        guard fm.fileExists(atPath: dest.path) else {
            throw StagingError.sourceMissing
        }
        return dest
    }

    /// Ask iCloud to download a placeholder before we try to read it. Best
    /// effort: a local file (or a provider that ignores this) just returns.
    private static func materializeIfNeeded(_ url: URL) {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// `name`, `name_1`, `name_2`, … — first one that is free in `dir`.
    private static func uniqueName(for name: String, in dir: URL) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.appendingPathComponent(name).path) { return name }
        let ns = name as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension
        var counter = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) { return candidate }
            counter += 1
        }
    }
}
