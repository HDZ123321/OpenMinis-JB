import Foundation

/// Reads and writes PendingShare data to the App Group shared container.
/// Compiled into both the main app target and the Share Extension target.
enum SharedContainerStore {
    static let appGroupID = "group.com.openminis.app"

    private static let pendingShareKey = "pendingShare"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Directory in the shared container for transferring attachment files.
    static var sharedFileDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("ShareExtension", isDirectory: true)
    }

    /// Directory that must exist for the app to run, resolved without ever
    /// returning nil.
    ///
    /// [T-jb-appgroup-fallback] `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// returns nil whenever the running binary was signed without the
    /// `com.apple.security.application-groups` entitlement — a free-tier
    /// Personal Team profile, an ad-hoc signature, or any re-sign that drops
    /// the group. Callers used to force-unwrap it, so such a build died on
    /// launch. Falling back to Application Support keeps every path valid;
    /// the directory simply stops being visible to the FileProvider
    /// extension and the share extension, which is the only thing an App
    /// Group actually buys us.
    static func sharedDirectory(_ component: String) -> URL {
        let base: URL
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            base = group
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            base = support.appendingPathComponent("MinisLocal", isDirectory: true)
        }
        let url = base.appendingPathComponent(component, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Write (called by Share Extension)

    static func savePendingShare(_ share: PendingShare) {
        guard let defaults = sharedDefaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(share) {
            defaults.set(data, forKey: pendingShareKey)
            defaults.synchronize()
        }
    }

    // MARK: - Read & Consume (called by main app)

    static func loadPendingShare() -> PendingShare? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: pendingShareKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingShare.self, from: data)
    }

    static func clearPendingShare() {
        sharedDefaults?.removeObject(forKey: pendingShareKey)
        sharedDefaults?.synchronize()
    }

    /// Remove all files from the shared transfer directory.
    static func cleanSharedFiles() {
        guard let dir = sharedFileDirectory else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }
}
