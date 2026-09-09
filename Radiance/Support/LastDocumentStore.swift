#if os(iOS)
import Foundation

// Remembers the last opened document so cold launches reopen it.
enum LastDocumentStore {
    private static let key = "lastDocumentBookmark"
    private static var didAttemptRestore = false

    static func save(_ url: URL) {
        guard let bookmark = try? url.bookmarkData() else {
            return
        }
        UserDefaults.standard.set(bookmark, forKey: key)
    }

    // Returns the last document URL once per launch, with security scope started.
    static func restoreOnce() -> URL? {
        guard !didAttemptRestore else {
            return nil
        }
        didAttemptRestore = true
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        if isStale {
            save(url)
        }
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        return url
    }
}
#endif
