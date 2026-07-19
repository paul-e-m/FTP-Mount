import Foundation

enum TransferProtocol: String, Codable, CaseIterable, Identifiable {
    case ftp = "FTP"
    case sftp = "SFTP"
    case webdav = "WebDAV"

    var id: String { rawValue }
    var defaultPort: Int {
        switch self {
        case .ftp: 21
        case .sftp: 22
        case .webdav: 443
        }
    }
    var rcloneType: String { rawValue.lowercased() }
    var usesServerURL: Bool { self == .webdav }
}

enum WebDAVVendor: String, Codable, CaseIterable, Identifiable {
    case other = "Other"
    case nextcloud = "Nextcloud"
    case owncloud = "ownCloud"
    case fastmail = "Fastmail Files"
    case sharepoint = "SharePoint Online"
    case sharepointNTLM = "SharePoint (NTLM)"

    var id: String { rawValue }
    var rcloneValue: String {
        switch self {
        case .other: "other"
        case .nextcloud: "nextcloud"
        case .owncloud: "owncloud"
        case .fastmail: "fastmail"
        case .sharepoint: "sharepoint"
        case .sharepointNTLM: "sharepoint-ntlm"
        }
    }
}

struct Bookmark: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var transferProtocol: TransferProtocol
    var server: String
    var port: Int?
    var username: String
    var rootDirectory: String
    var verifySFTPHostKey: Bool
    var webDAVVendor: WebDAVVendor
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "New Connection",
        transferProtocol: TransferProtocol = .sftp,
        server: String = "",
        port: Int? = nil,
        username: String = "",
        rootDirectory: String = "",
        verifySFTPHostKey: Bool = true,
        webDAVVendor: WebDAVVendor = .other,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.transferProtocol = transferProtocol
        self.server = server
        self.port = port
        self.username = username
        self.rootDirectory = rootDirectory
        self.verifySFTPHostKey = verifySFTPHostKey
        self.webDAVVendor = webDAVVendor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var effectivePort: Int { port ?? transferProtocol.defaultPort }

    var normalizedRoot: String {
        rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if transferProtocol == .webdav {
            guard let url = URL(string: server), let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else {
                return false
            }
            return true
        }
        return effectivePort > 0 && effectivePort <= 65_535
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, transferProtocol, server, port, username, rootDirectory
        case verifySFTPHostKey, webDAVVendor, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        transferProtocol = try values.decode(TransferProtocol.self, forKey: .transferProtocol)
        server = try values.decode(String.self, forKey: .server)
        port = try values.decodeIfPresent(Int.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        rootDirectory = try values.decode(String.self, forKey: .rootDirectory)
        verifySFTPHostKey = try values.decodeIfPresent(Bool.self, forKey: .verifySFTPHostKey) ?? true
        webDAVVendor = try values.decodeIfPresent(WebDAVVendor.self, forKey: .webDAVVendor) ?? .other
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

enum MountState: Equatable {
    case unmounted
    case mounting
    case mounted(URL)
    case unmounting
    case failed(String)

    var isMounted: Bool {
        if case .mounted = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unmounted: return "Not mounted"
        case .mounting: return "Mounting…"
        case .mounted: return "Mounted"
        case .unmounting: return "Unmounting…"
        case .failed(let message): return message
        }
    }
}
