import Foundation

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var lastError: String?

    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("FTP Mount", isDirectory: true)
        self.storageURL = directory.appendingPathComponent("bookmarks.json")
        load()
    }

    func bookmark(id: UUID) -> Bookmark? {
        bookmarks.first { $0.id == id }
    }

    @discardableResult
    func add() -> Bookmark {
        let bookmark = Bookmark()
        bookmarks.append(bookmark)
        persist()
        return bookmark
    }

    func save(_ bookmark: Bookmark, password: String?) throws {
        var updated = bookmark
        updated.updatedAt = Date()
        if let index = bookmarks.firstIndex(where: { $0.id == updated.id }) {
            bookmarks[index] = updated
        } else {
            bookmarks.append(updated)
        }
        if let password { try KeychainStore.shared.setPassword(password, for: updated.id) }
        try persistThrowing()
    }

    func delete(_ bookmark: Bookmark) throws {
        bookmarks.removeAll { $0.id == bookmark.id }
        try KeychainStore.shared.deletePassword(for: bookmark.id)
        try persistThrowing()
    }

    func password(for bookmark: Bookmark) throws -> String {
        try KeychainStore.shared.password(for: bookmark.id) ?? ""
    }

    private func load() {
        do {
            guard fileManager.fileExists(atPath: storageURL.path) else { return }
            let data = try Data(contentsOf: storageURL)
            bookmarks = try JSONDecoder.freeTP.decode([Bookmark].self, from: data)
        } catch {
            lastError = "Could not load bookmarks: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do { try persistThrowing() }
        catch { lastError = "Could not save bookmarks: \(error.localizedDescription)" }
    }

    private func persistThrowing() throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.freeTP.encode(bookmarks)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }
}

private extension JSONEncoder {
    static var freeTP: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var freeTP: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
